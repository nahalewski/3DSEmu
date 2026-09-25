// The DS: the melonDS core (melonDS-android-lib) run one frame at a time
// for emucore, and the Platform functions the core asks its frontend for.
//
// BIOS and firmware: the real ones from the system folder when they are
// there (bios7.bin, bios9.bin, firmware.bin), else the core's free BIOS and
// a generated firmware whose user settings (nickname, language, colour,
// birthday) come from the settings.  Saves are the game's save file,
// written a moment after the game last wrote to it, and on close.

#include <algorithm>
#include <chrono>
#include <codecvt>
#include <condition_variable>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <locale>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <dlfcn.h>
#include <sys/stat.h>

#include "Args.h"
#include "GPU3D_Soft.h"
#include "NDS.h"
#include "NDSCart.h"
#include "Platform.h"
#include "SPI_Firmware.h"
#include "Savestate.h"
#include "emucore_internal.h"

using namespace melonDS;

namespace {

struct DsState {
    std::unique_ptr<NDS> nds;
    std::string savePath;
    std::string firmwarePath;     // a real firmware's file (its settings are saved back)
    std::vector<u8> save;         // the save memory as the game last wrote it
    bool saveDirty = false;
    std::chrono::steady_clock::time_point dirtyAt;
    std::vector<u8> fb[2];        // the screens as RGBA
    u32 keys = 0;
    bool touching = false;
};

DsState* g = nullptr;

bool readFile(const std::string& path, std::vector<u8>& out)
{
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) return false;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (n < 0) { fclose(f); return false; }
    out.resize((size_t)n);
    bool ok = n == 0 || fread(out.data(), 1, (size_t)n, f) == (size_t)n;
    fclose(f);
    return ok;
}

bool writeFile(const std::string& path, const u8* data, size_t len)
{
    std::string tmp = path + ".part";
    FILE* f = fopen(tmp.c_str(), "wb");
    if (!f) return false;
    bool ok = len == 0 || fwrite(data, 1, len, f) == len;
    ok = fclose(f) == 0 && ok;
    return ok && rename(tmp.c_str(), path.c_str()) == 0;
}

std::u16string utf16(const std::string& s)
{
    try {
        return std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t>{}.from_bytes(s);
    } catch (...) {
        return u"";
    }
}

// the generated firmware's user settings, from the settings
void customize(Firmware& fw)
{
    auto& u = fw.GetEffectiveUserData();
    std::u16string name = utf16(ec_opt("ds.nickname", "Player"));
    if (!name.empty()) {
        size_t n = std::min<size_t>(name.size(), 10);
        memset(u.Nickname, 0, sizeof u.Nickname);
        memcpy(u.Nickname, name.data(), n * sizeof(char16_t));
        u.NameLength = (u16)n;
    }
    std::u16string msg = utf16(ec_opt("ds.message", ""));
    memset(u.Message, 0, sizeof u.Message);
    size_t m = std::min<size_t>(msg.size(), 26);
    memcpy(u.Message, msg.data(), m * sizeof(char16_t));
    u.MessageLength = (u16)m;
    int lang = atoi(ec_opt("ds.language", "1"));   // 0 JP, 1 EN, 2 FR, 3 DE, 4 IT, 5 ES
    if (lang >= 0 && lang <= 5) {
        u.Settings &= ~Firmware::Language::Reserved;
        u.Settings |= (u16)lang;
    }
    int color = atoi(ec_opt("ds.color", "0"));
    if (color >= 0 && color < 16) u.FavoriteColor = (u8)color;
    int bm = atoi(ec_opt("ds.birth_month", "1")), bd = atoi(ec_opt("ds.birth_day", "1"));
    if (bm >= 1 && bm <= 12) u.BirthdayMonth = (u8)bm;
    if (bd >= 1 && bd <= 31) u.BirthdayDay = (u8)bd;
    u.UpdateChecksum();
    fw.UpdateChecksums();
}

bool fileExists(const std::string& p)
{
    struct stat st;
    return stat(p.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

void toRgba(const u32* src, std::vector<u8>& dst)
{
    dst.resize(256 * 192 * 4);
    u8* d = dst.data();
    for (int i = 0; i < 256 * 192; i++) {
        u32 p = src[i];                  // 0xAARRGGBB
        d[i * 4 + 0] = (u8)(p >> 16);
        d[i * 4 + 1] = (u8)(p >> 8);
        d[i * 4 + 2] = (u8)p;
        d[i * 4 + 3] = 255;
    }
}

} // namespace

// ---------------------------------------------------------------- emucore

int ds_open(const char* rom, const char* save, const char* sysdir)
{
    ds_close();
    auto* s = new DsState();
    std::vector<u8> romData;
    if (!readFile(rom, romData) || romData.size() < 0x200 || romData.size() > 0x20000000u) {
        ec_set_error("could not read the game");
        delete s;
        return 0;
    }
    s->savePath = save ? save : "";
    readFile(s->savePath, s->save);

    NDSArgs args;
    std::string dir = sysdir ? sysdir : "";
    bool realBios = ec_opt_bool("ds.real_bios", true) && !dir.empty()
        && fileExists(dir + "/bios7.bin") && fileExists(dir + "/bios9.bin");
    if (realBios) {
        std::vector<u8> b7, b9;
        readFile(dir + "/bios7.bin", b7);
        readFile(dir + "/bios9.bin", b9);
        if (b7.size() == ARM7BIOSSize && b9.size() == ARM9BIOSSize) {
            args.ARM7BIOS = std::make_unique<ARM7BIOSImage>();
            args.ARM9BIOS = std::make_unique<ARM9BIOSImage>();
            memcpy(args.ARM7BIOS->data(), b7.data(), ARM7BIOSSize);
            memcpy(args.ARM9BIOS->data(), b9.data(), ARM9BIOSSize);
        } else {
            realBios = false;
        }
    }
    bool realFirmware = false;
    if (realBios && fileExists(dir + "/firmware.bin")) {
        std::vector<u8> fw;
        readFile(dir + "/firmware.bin", fw);
        Firmware firmware(fw.data(), (u32)fw.size());
        if (firmware.Buffer()) {
            args.Firmware = std::move(firmware);
            s->firmwarePath = dir + "/firmware.bin";
            realFirmware = true;
        }
    }
    if (!realFirmware) {
        args.Firmware = Firmware(0);
        customize(args.Firmware);
    }
    if (ec_opt_bool("ds.jit", true)) {
        args.JIT = JITArgs();
        args.JIT->MaxBlockSize = (unsigned)std::max(1, std::min(32, atoi(ec_opt("ds.jit_block", "32"))));
    } else {
        args.JIT = std::nullopt;
    }
    args.OutputSampleRate = 48000.0;
    args.Interpolation = (AudioInterpolation)std::max(0, std::min(4, atoi(ec_opt("ds.audio_interp", "1"))));
    args.Renderer3D = std::make_unique<SoftRenderer>();

    s->nds = std::make_unique<NDS>(std::move(args), s);
    g = s;
    if (auto* soft = dynamic_cast<SoftRenderer*>(&s->nds->GetRenderer3D()))
        soft->SetThreaded(ec_opt_bool("ds.threaded_3d", true), s->nds->GPU);
    s->nds->Reset();

    NDSCart::NDSCartArgs cartArgs{};
    if (!s->save.empty()) {
        cartArgs.SRAM = std::make_unique<u8[]>(s->save.size());
        memcpy(cartArgs.SRAM.get(), s->save.data(), s->save.size());
        cartArgs.SRAMLength = (u32)s->save.size();
    }
    auto cart = NDSCart::ParseROM(romData.data(), (u32)romData.size(), s, std::move(cartArgs));
    if (!cart) {
        ec_set_error("not a DS game this can play");
        ds_close();
        return 0;
    }
    s->nds->SetNDSCart(std::move(cart));
    if (!realBios || !realFirmware || s->nds->NeedsDirectBoot() || !ec_opt_bool("ds.boot_menu", false)) {
        std::string name = rom;
        size_t slash = name.find_last_of('/');
        if (slash != std::string::npos) name = name.substr(slash + 1);
        s->nds->SetupDirectBoot(name);
    }
    time_t now = time(nullptr);
    struct tm lt;
    localtime_r(&now, &lt);
    s->nds->RTC.SetDateTime(lt.tm_year + 1900, lt.tm_mon + 1, lt.tm_mday, lt.tm_hour, lt.tm_min, lt.tm_sec);
    s->nds->SPU.SetOutputSampleRate(48000.0);
    s->nds->Start();
    s->keys = 0;
    return 1;
}

void ds_close()
{
    if (!g) return;
    ds_flush(true);
    DsState* s = g;
    if (s->nds) s->nds->Stop();
    s->nds.reset();
    g = nullptr;
    delete s;
}

void ds_set_keys(uint32_t pressed)
{
    if (!g) return;
    g->keys = pressed;
    g->nds->SetKeyMask(~pressed & 0xFFF);
    g->nds->SetLidClosed((pressed & EC_KEY_LID) != 0);
}

void ds_touch(int down, int x, int y)
{
    if (!g) return;
    if (down) {
        g->nds->TouchScreen((u16)std::max(0, std::min(255, x)), (u16)std::max(0, std::min(191, y)));
        g->touching = true;
    } else if (g->touching) {
        g->nds->ReleaseScreen();
        g->touching = false;
    }
}

void ds_run_frame()
{
    if (!g) return;
    g->nds->RunFrame();
    int front = g->nds->GPU.FrontBuffer;
    for (int i = 0; i < 2; i++) {
        const u32* src = g->nds->GPU.Framebuffer[front][i].get();
        if (src) toRgba(src, g->fb[i]);
        else g->fb[i].assign(256 * 192 * 4, 0);
    }
    ds_flush(false);
}

const uint8_t* ds_screen(int idx, int* w, int* h)
{
    if (!g || idx < 0 || idx > 1 || g->fb[idx].empty()) return nullptr;
    *w = 256;
    *h = 192;
    return g->fb[idx].data();
}

int ds_audio(int16_t* out, int max_frames)
{
    if (!g) return 0;
    return g->nds->SPU.ReadOutput(out, max_frames);
}

// the save to its file a second after the game's last write (a game writes
// its save in many small pieces), or now when closing
void ds_flush(bool now)
{
    if (!g || !g->saveDirty || g->savePath.empty()) return;
    if (!now && std::chrono::steady_clock::now() - g->dirtyAt < std::chrono::seconds(1)) return;
    if (writeFile(g->savePath, g->save.data(), g->save.size())) g->saveDirty = false;
}

int ds_save_state(const char* path)
{
    if (!g) return 0;
    Savestate st;
    if (st.Error || !g->nds->DoSavestate(&st) || st.Error) return 0;
    st.Finish();
    return writeFile(path, (const u8*)st.Buffer(), st.Length()) ? 1 : 0;
}

int ds_load_state(const char* path)
{
    if (!g) return 0;
    std::vector<u8> data;
    if (!readFile(path, data) || data.empty()) return 0;
    Savestate st(data.data(), (u32)data.size(), false);
    if (st.Error) return 0;
    return g->nds->DoSavestate(&st) && !st.Error ? 1 : 0;
}

void ds_reset()
{
    if (!g) return;
    g->nds->Reset();
    g->nds->Start();
}

// ---------------------------------------------------------------- Platform

namespace melonDS::Platform {

void SignalStop(StopReason, void*) {}

struct FileHandle { FILE* f; };

static const char* modeString(FileMode mode)
{
    bool read = mode & FileMode::Read, write = mode & FileMode::Write;
    bool keep = mode & FileMode::Preserve, append = mode & FileMode::Append;
    if (append) return read ? "a+b" : "ab";
    if (read && write) return keep ? "r+b" : "w+b";
    if (write) return keep ? "r+b" : "wb";
    return "rb";
}

FileHandle* OpenFile(const std::string& path, FileMode mode)
{
    if ((mode & FileMode::ReadWrite) == FileMode::None) return nullptr;
    bool exists = fileExists(path);
    if ((mode & FileMode::NoCreate) && !exists) return nullptr;
    const char* m = modeString(mode);
    // "r+" needs the file: make it first when creating is allowed
    if (!exists && m[0] == 'r' && m[1] == '+') {
        FILE* c = fopen(path.c_str(), "wb");
        if (!c) return nullptr;
        fclose(c);
    }
    FILE* f = fopen(path.c_str(), m);
    if (!f) return nullptr;
    return new FileHandle{f};
}

std::string GetLocalFilePath(const std::string& filename)
{
    std::string dir = ec_opt("sysdir", "");
    if (dir.empty() || (!filename.empty() && filename[0] == '/')) return filename;
    return dir + "/" + filename;
}

FileHandle* OpenLocalFile(const std::string& path, FileMode mode) { return OpenFile(GetLocalFilePath(path), mode); }
bool FileExists(const std::string& name) { return fileExists(name); }
bool LocalFileExists(const std::string& name) { return fileExists(GetLocalFilePath(name)); }

bool CheckFileWritable(const std::string& filepath)
{
    FILE* f = fopen(filepath.c_str(), "ab");
    if (!f) return false;
    fclose(f);
    return true;
}

bool CheckLocalFileWritable(const std::string& filepath) { return CheckFileWritable(GetLocalFilePath(filepath)); }

bool CloseFile(FileHandle* file)
{
    if (!file) return false;
    bool ok = fclose(file->f) == 0;
    delete file;
    return ok;
}

bool IsEndOfFile(FileHandle* file) { return feof(file->f) != 0; }
bool FileReadLine(char* str, int count, FileHandle* file) { return fgets(str, count, file->f) != nullptr; }
u64 FilePosition(FileHandle* file) { return (u64)ftell(file->f); }

bool FileSeek(FileHandle* file, s64 offset, FileSeekOrigin origin)
{
    int w = origin == FileSeekOrigin::Start ? SEEK_SET : origin == FileSeekOrigin::Current ? SEEK_CUR : SEEK_END;
    return fseek(file->f, (long)offset, w) == 0;
}

void FileRewind(FileHandle* file) { rewind(file->f); }
u64 FileRead(void* data, u64 size, u64 count, FileHandle* file) { return fread(data, size, count, file->f); }
bool FileFlush(FileHandle* file) { return fflush(file->f) == 0; }
u64 FileWrite(const void* data, u64 size, u64 count, FileHandle* file) { return fwrite(data, size, count, file->f); }

u64 FileWriteFormatted(FileHandle* file, const char* fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vfprintf(file->f, fmt, ap);
    va_end(ap);
    return n < 0 ? 0 : (u64)n;
}

u64 FileLength(FileHandle* file)
{
    long pos = ftell(file->f);
    fseek(file->f, 0, SEEK_END);
    long len = ftell(file->f);
    fseek(file->f, pos, SEEK_SET);
    return len < 0 ? 0 : (u64)len;
}

void Log(LogLevel level, const char* fmt, ...)
{
    if (level == LogLevel::Debug) return;
    va_list ap;
    va_start(ap, fmt);
    ec_logv(fmt, ap);
    va_end(ap);
}

struct Thread { std::thread t; };
Thread* Thread_Create(std::function<void()> func) { return new Thread{std::thread(std::move(func))}; }
void Thread_Free(Thread* thread)
{
    if (!thread) return;
    if (thread->t.joinable()) thread->t.detach();
    delete thread;
}
void Thread_Wait(Thread* thread) { if (thread && thread->t.joinable()) thread->t.join(); }

struct Semaphore {
    std::mutex m;
    std::condition_variable cv;
    int count = 0;
};
Semaphore* Semaphore_Create() { return new Semaphore(); }
void Semaphore_Free(Semaphore* sema) { delete sema; }
void Semaphore_Reset(Semaphore* sema)
{
    std::lock_guard<std::mutex> l(sema->m);
    sema->count = 0;
}
void Semaphore_Wait(Semaphore* sema)
{
    std::unique_lock<std::mutex> l(sema->m);
    sema->cv.wait(l, [sema] { return sema->count > 0; });
    sema->count--;
}
bool Semaphore_TryWait(Semaphore* sema, int timeout_ms)
{
    std::unique_lock<std::mutex> l(sema->m);
    if (!sema->cv.wait_for(l, std::chrono::milliseconds(timeout_ms), [sema] { return sema->count > 0; }))
        return false;
    sema->count--;
    return true;
}
void Semaphore_Post(Semaphore* sema, int count)
{
    {
        std::lock_guard<std::mutex> l(sema->m);
        sema->count += count;
    }
    for (int i = 0; i < count; i++) sema->cv.notify_one();
}

struct Mutex { std::mutex m; };
Mutex* Mutex_Create() { return new Mutex(); }
void Mutex_Free(Mutex* mutex) { delete mutex; }
void Mutex_Lock(Mutex* mutex) { mutex->m.lock(); }
void Mutex_Unlock(Mutex* mutex) { mutex->m.unlock(); }
bool Mutex_TryLock(Mutex* mutex) { return mutex->m.try_lock(); }

void Sleep(u64 usecs) { std::this_thread::sleep_for(std::chrono::microseconds(usecs)); }

u64 GetMSCount()
{
    return (u64)std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

u64 GetUSCount()
{
    return (u64)std::chrono::duration_cast<std::chrono::microseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

void WriteNDSSave(const u8* savedata, u32 savelen, u32, u32, void* userdata)
{
    auto* s = (DsState*)userdata;
    if (!s || !savedata) return;
    s->save.assign(savedata, savedata + savelen);
    s->saveDirty = true;
    s->dirtyAt = std::chrono::steady_clock::now();
}

void WriteGBASave(const u8*, u32, u32, u32, void*) {}

void WriteFirmware(const Firmware& firmware, u32, u32, void* userdata)
{
    // the settings a game or the DS menu changed, kept in a real firmware's
    // file; a generated one is made afresh from the settings each time
    auto* s = (DsState*)userdata;
    if (!s || s->firmwarePath.empty()) return;
    writeFile(s->firmwarePath, firmware.Buffer(), firmware.Length());
}

void WriteDateTime(int, int, int, int, int, int, void*) {}

// local wireless play, Wi-Fi, cameras, microphone, add-ons: none (a quiet
// room with no other DS in it)
void MP_Begin(void*) {}
void MP_End(void*) {}
int MP_SendPacket(u8*, int len, u64, void*) { return len; }
int MP_RecvPacket(u8*, u64*, void*) { return 0; }
int MP_SendCmd(u8*, int len, u64, void*) { return len; }
int MP_SendReply(u8*, int len, u64, u16, void*) { return len; }
int MP_SendAck(u8*, int len, u64, void*) { return len; }
int MP_RecvHostPacket(u8*, u64*, void*) { return 0; }
u16 MP_RecvReplies(u8*, u64, u16, void*) { return 0; }
int Net_SendPacket(u8*, int len, void*) { return len; }
int Net_RecvPacket(u8*, void*) { return 0; }

void Camera_Start(int, void*) {}
void Camera_Stop(int, void*) {}
void Camera_CaptureFrame(int, u32* frame, int width, int height, bool, void*)
{
    if (frame) memset(frame, 0, (size_t)width * height * sizeof(u32));
}

void Mic_Start(void*) {}
void Mic_Stop(void*) {}
int Mic_ReadInput(s16* data, int maxlength, void*)
{
    if (data && maxlength > 0) memset(data, 0, (size_t)maxlength * sizeof(s16));
    return maxlength;
}

AACDecoder* AAC_Init() { return nullptr; }
void AAC_DeInit(AACDecoder*) {}
bool AAC_Configure(AACDecoder*, int, int) { return false; }
bool AAC_DecodeFrame(AACDecoder*, const void*, int, void*, int) { return false; }

bool Addon_KeyDown(KeyType, void*) { return false; }
void Addon_RumbleStart(u32, void*) {}
void Addon_RumbleStop(void*) {}
float Addon_MotionQuery(MotionQueryType type, void*)
{
    // lying flat, still: 1 g straight down
    return type == MotionAccelerationZ ? 9.80665f : 0.0f;
}

// the JIT's fast memory asks for libandroid.so's ASharedMemory_create
DynamicLibrary* DynamicLibrary_Load(const char* lib)
{
    return (DynamicLibrary*)dlopen(lib, RTLD_NOW | RTLD_LOCAL);
}
void DynamicLibrary_Unload(DynamicLibrary* lib)
{
    if (lib) dlclose(lib);
}
void* DynamicLibrary_LoadFunction(DynamicLibrary* lib, const char* name)
{
    return lib ? dlsym(lib, name) : nullptr;
}

} // namespace melonDS::Platform
