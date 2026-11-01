// Lit et pilote « À l'écoute » (MediaRemote) depuis /usr/bin/perl, seul hôte autorisé par macOS.
// Trois points d'entrée, appelés par now-playing.pl :
//   pastille_now_playing : un instantané en JSON, puis fin ;
//   pastille_stream      : une ligne JSON à chaque changement (morceau, lecture, position, app), sans fin ;
//   pastille_command     : une commande lue dans $PASTILLE_ARG (« toggle », « next », « previous », « seek:12.5 »).
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*GetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendCommandFn)(int, CFDictionaryRef);
typedef void (*SetElapsedFn)(double);

static void *mediaRemote(void) {
    static void *handle;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    return handle;
}

static void *symbol(const char *name) {
    void *handle = mediaRemote();
    return handle ? dlsym(handle, name) : NULL;
}

static void writeLine(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

/// Rassemble titre, position, état de lecture et app ; `includeArtwork` à NO pour ne pas renvoyer une pochette inchangée.
static void snapshot(BOOL (^includeArtwork)(NSData *artwork), void (^completion)(NSDictionary *)) {
    GetInfoFn getInfo = (GetInfoFn)symbol("MRMediaRemoteGetNowPlayingInfo");
    GetBoolFn getPlaying = (GetBoolFn)symbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    GetPIDFn getPID = (GetPIDFn)symbol("MRMediaRemoteGetNowPlayingApplicationPID");
    if (!getInfo) { completion(@{}); return; }

    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    dispatch_group_t group = dispatch_group_create();
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSObject *lock = [NSObject new];

    dispatch_group_enter(group);
    getInfo(queue, ^(CFDictionaryRef info) {
        NSDictionary *d = (__bridge NSDictionary *)info;
        @synchronized (lock) {
            NSDictionary *keys = @{
                @"kMRMediaRemoteNowPlayingInfoTitle": @"title",
                @"kMRMediaRemoteNowPlayingInfoArtist": @"artist",
                @"kMRMediaRemoteNowPlayingInfoAlbum": @"album",
                @"kMRMediaRemoteNowPlayingInfoDuration": @"duration",
                @"kMRMediaRemoteNowPlayingInfoElapsedTime": @"elapsed",
                @"kMRMediaRemoteNowPlayingInfoPlaybackRate": @"rate",
            };
            [keys enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *name, BOOL *stop) {
                id value = d[key];
                if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) out[name] = value;
            }];
            NSDate *timestamp = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
            if ([timestamp isKindOfClass:NSDate.class]) out[@"timestamp"] = @(timestamp.timeIntervalSince1970);
            NSData *artwork = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if ([artwork isKindOfClass:NSData.class] && artwork.length > 0) {
                out[@"artworkHash"] = @(artwork.hash ^ artwork.length);
                if (includeArtwork(artwork)) out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
            }
        }
        dispatch_group_leave(group);
    });
    if (getPlaying) {
        dispatch_group_enter(group);
        getPlaying(queue, ^(Boolean playing) {
            @synchronized (lock) { out[@"playing"] = @(playing); }
            dispatch_group_leave(group);
        });
    }
    if (getPID) {
        dispatch_group_enter(group);
        getPID(queue, ^(int pid) {
            NSRunningApplication *app = pid > 0 ? [NSRunningApplication runningApplicationWithProcessIdentifier:pid] : nil;
            @synchronized (lock) {
                if (app.bundleIdentifier) out[@"bundle"] = app.bundleIdentifier;
                if (app.localizedName) out[@"app"] = app.localizedName;
            }
            dispatch_group_leave(group);
        });
    }
    dispatch_group_notify(group, queue, ^{
        NSDictionary *result;
        @synchronized (lock) { result = [out copy]; }
        completion(result);
    });
}

void pastille_now_playing(void *perl, void *cv) {
    @autoreleasepool {
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block NSDictionary *result = @{};
        snapshot(^BOOL(NSData *artwork) { return YES; }, ^(NSDictionary *info) {
            result = info;
            dispatch_semaphore_signal(done);
        });
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        writeLine(result);
    }
}

void pastille_stream(void *perl, void *cv) {
    RegisterFn registerFn = (RegisterFn)symbol("MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!registerFn) return;
    registerFn(dispatch_get_main_queue());

    __block NSNumber *lastArtwork = nil;
    __block BOOL scheduled = NO;
    // Les notifications arrivent souvent en rafale : on regroupe sur 80 ms.
    void (^emit)(void) = ^{
        if (scheduled) return;
        scheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            scheduled = NO;
            snapshot(^BOOL(NSData *artwork) {
                NSNumber *hash = @(artwork.hash ^ artwork.length);
                return ![hash isEqual:lastArtwork];
            }, ^(NSDictionary *info) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (info[@"artwork"]) lastArtwork = info[@"artworkHash"];
                    if (!info[@"artworkHash"]) lastArtwork = nil;
                    writeLine(info);
                });
            });
        });
    };

    const char *names[] = {
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        CFStringRef *name = (CFStringRef *)symbol(names[i]);
        if (!name || !*name) continue;
        [NSNotificationCenter.defaultCenter addObserverForName:(__bridge NSString *)*name object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { emit(); }];
    }
    emit();
    // Si Pastille quitte, l'écriture échoue (SIGPIPE) et ce processus s'arrête avec elle.
    CFRunLoopRun();
}

void pastille_command(void *perl, void *cv) {
    const char *raw = getenv("PASTILLE_ARG");
    if (!raw) return;
    NSString *command = @(raw);
    if ([command hasPrefix:@"seek:"]) {
        SetElapsedFn setElapsed = (SetElapsedFn)symbol("MRMediaRemoteSetElapsedTime");
        if (setElapsed) setElapsed([[command substringFromIndex:5] doubleValue]);
    } else {
        // Codes MRCommand : 2 = lecture/pause, 4 = suivant, 5 = précédent.
        NSDictionary *codes = @{ @"toggle": @2, @"next": @4, @"previous": @5 };
        NSNumber *code = codes[command];
        SendCommandFn send = (SendCommandFn)symbol("MRMediaRemoteSendCommand");
        if (code && send) send(code.intValue, NULL);
    }
    // L'ordre part de façon asynchrone : on laisse le temps à macOS de le transmettre avant de quitter.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
}
