#import "DawnMeshInternetDSP.h"
#import <flutter_webrtc/AudioManager.h>
#import <flutter_webrtc/AudioProcessingAdapter.h>
#import <DawnMeshNative/DawnMeshAudio.h>
#include <mutex>
#include <vector>

@interface DawnMeshInternetDSP () <ExternalAudioProcessingDelegate>
@end
@implementation DawnMeshInternetDSP {
    std::mutex _lock;
    std::vector<void*> _states;
    int _rate;
    int _level;
    BOOL _attached;
}
+ (instancetype)shared {
    static DawnMeshInternetDSP *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [DawnMeshInternetDSP new]; });
    return instance;
}
- (void)start:(int)level {
    [self setLevel:level];
    if (!_attached) {
        [[AudioManager sharedInstance].capturePostProcessingAdapter addProcessing:self];
        _attached = YES;
    }
}
- (void)stop {
    if (_attached) {
        [[AudioManager sharedInstance].capturePostProcessingAdapter removeProcessing:self];
        _attached = NO;
    }
    [self audioProcessingRelease];
}
- (void)setLevel:(int)level { std::lock_guard<std::mutex> guard(_lock); _level = MAX(0, MIN(2, level)); }
- (void)resetForRate:(int)rate channels:(int)channels {
    for (void *state : _states) dm_denoiser_free(state);
    _states.clear();
    _rate = rate;
    for (int index = 0; index < channels; index++) _states.push_back(dm_denoiser_create(rate));
}
- (void)audioProcessingInitializeWithSampleRate:(size_t)sampleRateHz channels:(size_t)channels {
    std::lock_guard<std::mutex> guard(_lock);
    [self resetForRate:(int)sampleRateHz channels:(int)channels];
}
- (void)audioProcessingProcess:(RTCAudioBuffer *)buffer {
    std::lock_guard<std::mutex> guard(_lock);
    const int rate = (int)buffer.frames * 100;
    if (_rate != rate || _states.size() != buffer.channels) [self resetForRate:rate channels:(int)buffer.channels];
    for (size_t index = 0; index < _states.size(); index++)
        if (_states[index]) dm_denoise_float(_states[index], [buffer rawBufferForChannel:index], (int)buffer.frames, _level);
}
- (void)audioProcessingRelease {
    std::lock_guard<std::mutex> guard(_lock);
    [self resetForRate:0 channels:0];
}
@end
