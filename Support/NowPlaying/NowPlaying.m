// Lit « À l'écoute » (MediaRemote) depuis /usr/bin/perl, seul hôte autorisé par macOS.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));

void pastille_now_playing(void *perl, void *cv) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        GetInfoFn get = handle ? (GetInfoFn)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") : NULL;
        if (!get) return;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        get(dispatch_get_global_queue(0, 0), ^(CFDictionaryRef info) {
            NSDictionary *d = (__bridge NSDictionary *)info;
            NSString *title = d[@"kMRMediaRemoteNowPlayingInfoTitle"];
            NSString *artist = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
            NSData *art = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
            if (title) out[@"title"] = title;
            if (artist) out[@"artist"] = artist;
            if (art) out[@"artwork"] = [art base64EncodedStringWithOptions:0];
            dispatch_semaphore_signal(done);
        });
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
        fwrite(json.bytes, 1, json.length, stdout);
        fflush(stdout);
    }
}
