#include "audio_device_ios.h"

#include "objc/RTCAudioSession.h"
#include "media/module/utility/helpers_ios.h"

const double kIOBufferDuration = 0.01;  //10ms一帧
// Number of bytes per audio sample for 16-bit signed integer representation.
const UInt32 kBytesPerSample = 2;
// Calls to AudioUnitInitialize() can fail if called back-to-back on different
// ADM instances. A fall-back solution is to allow multiple sequential calls
// with as small delay between each. This factor sets the max number of allowed
// initialization attempts.
const int kMaxNumberOfAudioUnitInitializeAttempts = 5;
#define kPreferredNumberOfChannels  1   //单声道

#define DEBUG_MIC_AUDIO  0

AudioDevice* AudioDevice::Create()
{
    return new AudioDeviceIos();
}


// Verifies that the current audio session supports input audio and that the
// required category and mode are enabled.
static bool VerifyAudioSession(RTCAudioSession* session) {
    NSLog(@"VerifyAudioSession");
    // Ensure that the device currently supports audio input.
    if (!session.inputAvailable) {
        NSLog(@"No audio input path is available!");
        return false;
    }
    
    // Ensure that the required category and mode are actually activated.
    if (![session.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        NSLog(@"Failed to set category to AVAudioSessionCategoryPlayAndRecord");
        return false;
    }
    if (![session.mode isEqualToString:AVAudioSessionModeVoiceChat]) {
        NSLog(@"Failed to set mode to AVAudioSessionModeVoiceChat");
        return false;
    }
    return true;
}


AudioDeviceIos::AudioDeviceIos()
               :vpio_unit_(nullptr)
               ,recording_(false)
               ,playing_(0)
               ,initialized_(false)
               ,rec_is_initialized_(false)
               ,play_is_initialized_(false)
               ,audio_interruption_observer_(nullptr)
               ,route_change_observer_(nullptr)
               ,mic_to_wav_(nullptr)
{

}

AudioDeviceIos::~AudioDeviceIos()
{
    Destory();
}

void AudioDeviceIos::Init(int sample_rate,int channel)
{
    if (initialized_) {
        return;
    }
    sample_rate_=sample_rate;
    channel_=channel;
    initialized_ = true;
}

void AudioDeviceIos::InitPlayout(PcmPlayCb pcm_play_cb)
{
    if(play_is_initialized_)
        return;
    if (!rec_is_initialized_) {
        if (!InitPlayOrRecord()) {
            NSLog(@"InitPlayOrRecord failed for InitPlayout!");
            return;
        }
    }
    play_is_initialized_ = true;
    pcm_play_cb_=pcm_play_cb;
}

void AudioDeviceIos::InitRecording(PcmRecordCb pcm_record_cb)
{
    if(rec_is_initialized_)
        return;
    if (!play_is_initialized_) {
        if (!InitPlayOrRecord()) {
            NSLog(@"InitPlayOrRecord failed for InitRecording!");
            return;
        }
    }
    rec_is_initialized_ = true;
    pcm_record_cb_=pcm_record_cb;
    
}

int32_t AudioDeviceIos::StartPlayout()
{
    NSLog(@"StartPlayout");
    assert(play_is_initialized_);
    assert(!playing_.load());
    if (!recording_.load()) {
        OSStatus result = AudioOutputUnitStart(vpio_unit_);
        if (result != noErr) {
            NSLog(@"AudioOutputUnitStart failed for StartPlayout: %d",result);
            return -1;
        }
        NSLog(@"Voice-Processing I/O audio unit is now started");
    }
    playing_.store(true);
    return 0;
}

int32_t AudioDeviceIos::StopPlayout()
{
    NSLog(@"StopPlayout");
    if (!play_is_initialized_ || !playing_.load()) {
        return 0;
    }
    if (!recording_.load()) {
        ShutdownPlayOrRecord();
    }
    play_is_initialized_ = false;
    playing_.store(false);
    return 0;
}

int32_t AudioDeviceIos::StartRecording()
{
    NSLog(@"StartRecording");
    assert(rec_is_initialized_);
    assert(!recording_.load());
    if (!playing_.load()) {
        OSStatus result = AudioOutputUnitStart(vpio_unit_);
        if (result != noErr) {
            NSLog(@"AudioOutputUnitStart failed for StartRecording: %d",result);
            return -1;
        }
        NSLog(@"Voice-Processing I/O audio unit is now started");
    }
    recording_.store(true);
    
    if(DEBUG_MIC_AUDIO)
    {
        if(!mic_to_wav_)
        {
            NSArray *documentsPathArr = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsPath = [documentsPathArr lastObject];    // 拼接要写入文件的路径
            NSString *path = [documentsPath stringByAppendingPathComponent:@"mic_audio.wav"];
            const char* destDir = [path UTF8String];
            mic_to_wav_=new webrtc::WavWriter(destDir, sample_rate_, channel_);
        }
    }
    
    return 0;
}

int32_t AudioDeviceIos::StopRecording()
{
    NSLog(@"StopRecording");
    if (!rec_is_initialized_ || !recording_.load()) {
        return 0;
    }
    if (!playing_.load()) {
        ShutdownPlayOrRecord();
    }
    rec_is_initialized_ = false;
    recording_.store(false);
    
    if(DEBUG_MIC_AUDIO)
    {
        if(mic_to_wav_)
        {
            delete mic_to_wav_;
            mic_to_wav_=nullptr;
        }
    }
    
    return 0;
}

// Change the default receiver playout route to speaker.
int32_t AudioDeviceIos::SetLoudspeakerStatus(bool enable) {
    NSLog(@"SetLoudspeakerStatus:%d",enable);
    
    RTCAudioSession* session = [RTCAudioSession sharedInstance];
    [session lockForConfiguration];
    NSString* category = session.category;
    AVAudioSessionCategoryOptions options = session.categoryOptions;
    // Respect old category options if category is
    // AVAudioSessionCategoryPlayAndRecord. Otherwise reset it since old options
    // might not be valid for this category.
    if ([category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
        if (enable) {
            options |= AVAudioSessionCategoryOptionDefaultToSpeaker;
        } else {
            options &= ~AVAudioSessionCategoryOptionDefaultToSpeaker;
        }
    } else {
        options = AVAudioSessionCategoryOptionDefaultToSpeaker;
    }
    NSError* error = nil;
    BOOL success = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                            withOptions:options
                                  error:&error];
    CheckAndLogError(success, error);
    [session unlockForConfiguration];
    return (error == nil) ? 0 : -1;
}

void AudioDeviceIos::Destory()
{
    if (!initialized_) {
        return;
    }
    StopPlayout();
    StopRecording();
    initialized_ = false;
}

bool AudioDeviceIos::InitPlayOrRecord()
{
    NSLog(@"InitPlayOrRecord");
    // Activate the audio session if not already activated.
    if (!ActivateAudioSession(true)) {
        return false;
    }
    
    // Ensure that the active audio session has the correct category and mode.
    RTCAudioSession* session = [RTCAudioSession sharedInstance];
    if (!VerifyAudioSession(session)) {
        ActivateAudioSession(false);
        NSLog(@"Failed to verify audio session category and mode");
        return false;
    }
    
    // Start observing audio session interruptions and route changes.
    RegisterNotificationObservers();
    
    // Ensure that we got what what we asked for in our active audio session.
    SetupAudioBuffersForActiveAudioSession();
    
    // Create, setup and initialize a new Voice-Processing I/O unit.
    if (!SetupAndInitializeVoiceProcessingAudioUnit()) {
        // Reduce usage count for the audio session and possibly deactivate it if
        // this object is the only user.
        ActivateAudioSession(false);
        return false;
    }
    return true;
}

void AudioDeviceIos::ShutdownPlayOrRecord() {
    NSLog(@"ShutdownPlayOrRecord");
    // Close and delete the voice-processing I/O unit.
    OSStatus result = -1;
    if (nullptr != vpio_unit_) {
        result = AudioOutputUnitStop(vpio_unit_);
        if (result != noErr) {
            NSLog(@"AudioOutputUnitStop failed: %d",result);
        }
        result = AudioUnitUninitialize(vpio_unit_);
        if (result != noErr) {
            NSLog(@"AudioUnitUninitialize failed: %d",result);
        }
        DisposeAudioUnit();
    }
    
    // Remove audio session notification observers.
    UnregisterNotificationObservers();
    
    // All I/O should be stopped or paused prior to deactivating the audio
    // session, hence we deactivate as last action.
    ActivateAudioSession(false);
}

bool AudioDeviceIos::ActivateAudioSession(bool activate)
{
    NSLog(@"ActivateAudioSession:%d",activate);
    
    NSError* error = nil;
    BOOL success = NO;
    RTCAudioSession* session = [RTCAudioSession sharedInstance];
    [session lockForConfiguration];
    if (!activate) {
        success = [session setActive:NO
                               error:&error];
        [session unlockForConfiguration];
        return CheckAndLogError(success, error);
    }
    
    // Go ahead and active our own audio session since |activate| is true.
    // Use a category which supports simultaneous recording and playback.
    // By default, using this category implies that our app’s audio is
    // nonmixable, hence activating the session will interrupt any other
    // audio sessions which are also nonmixable.
    if (session.category != AVAudioSessionCategoryPlayAndRecord) {
        error = nil;
        success = [session setCategory:AVAudioSessionCategoryPlayAndRecord
                           withOptions:AVAudioSessionCategoryOptionAllowBluetooth
                                 error:&error];
        CheckAndLogError(success, error);
    }
    
    // Specify mode for two-way voice communication (e.g. VoIP).
    if (session.mode != AVAudioSessionModeVoiceChat) {
        error = nil;
        success = [session setMode:AVAudioSessionModeVoiceChat error:&error];
        CheckAndLogError(success, error);
    }
    
    // Set the session's sample rate or the hardware sample rate.
    // It is essential that we use the same sample rate as stream format
    // to ensure that the I/O unit does not have to do sample rate conversion.
    error = nil;
    success =
    [session setPreferredSampleRate:sample_rate_ error:&error];
    CheckAndLogError(success, error);
    
    // Set the preferred audio I/O buffer duration, in seconds.
    error = nil;
    success = [session setPreferredIOBufferDuration:kIOBufferDuration
                                              error:&error];
    CheckAndLogError(success, error);
    
    // Activate the audio session. Activation can fail if another active audio
    // session (e.g. phone call) has higher priority than ours.
    error = nil;
    success = [session setActive:YES error:&error];
    if (!CheckAndLogError(success, error)) {
        [session unlockForConfiguration];
        return false;
    }
    
    // Ensure that the active audio session has the correct category and mode.
    if (!VerifyAudioSession(session)) {
        NSLog(@"Failed to verify audio session category and mode");
        [session unlockForConfiguration];
        return false;
    }
    
    // Try to set the preferred number of hardware audio channels. These calls
    // must be done after setting the audio session’s category and mode and
    // activating the session.
    // We try to use mono in both directions to save resources and format
    // conversions in the audio unit. Some devices does only support stereo;
    // e.g. wired headset on iPhone 6.
    // TODO(henrika): add support for stereo if needed.
    error = nil;
    success =
    [session setPreferredInputNumberOfChannels:kPreferredNumberOfChannels
                                         error:&error];
    CheckAndLogError(success, error);

    error = nil;
    success =
    [session setPreferredOutputNumberOfChannels:kPreferredNumberOfChannels
                                          error:&error];
    CheckAndLogError(success, error);
    [session unlockForConfiguration];
    return true;
}

void AudioDeviceIos::RegisterNotificationObservers()
{
    NSLog(@"RegisterNotificationObservers");
    // This code block will be called when AVAudioSessionInterruptionNotification
    // is observed.
    void (^interrupt_block)(NSNotification*) = ^(NSNotification* notification) {
        NSNumber* type_number =
        notification.userInfo[AVAudioSessionInterruptionTypeKey];
        AVAudioSessionInterruptionType type =
        (AVAudioSessionInterruptionType)type_number.unsignedIntegerValue;
        NSLog(@"Audio session interruption:");
        switch (type) {
            case AVAudioSessionInterruptionTypeBegan:
                // The system has deactivated our audio session.
                // Stop the active audio unit.
                NSLog(@"Began => stopping the audio unit");
                AudioOutputUnitStop(vpio_unit_);
                break;
            case AVAudioSessionInterruptionTypeEnded:
                // The interruption has ended. Restart the audio session and start the
                // initialized audio unit again.
                NSLog(@" Ended => restarting audio session and audio unit");
                NSError* error = nil;
                BOOL success = NO;
                AVAudioSession* session = [AVAudioSession sharedInstance];
                success = [session setActive:YES error:&error];
                if (CheckAndLogError(success, error)) {
                   AudioOutputUnitStart(vpio_unit_);
                }
                break;
        }
    };
    
    // This code block will be called when AVAudioSessionRouteChangeNotification
    // is observed.
    void (^route_change_block)(NSNotification*) =
    ^(NSNotification* notification) {
        // Get reason for current route change.
        NSNumber* reason_number =
        notification.userInfo[AVAudioSessionRouteChangeReasonKey];
        AVAudioSessionRouteChangeReason reason =
        (AVAudioSessionRouteChangeReason)reason_number.unsignedIntegerValue;
        bool valid_route_change = true;
        NSLog(@"Route change:");
        switch (reason) {
            case AVAudioSessionRouteChangeReasonUnknown:
                NSLog(@" ReasonUnknown");
                break;
            case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
                NSLog(@" NewDeviceAvailable");
                break;
            case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
                NSLog(@" OldDeviceUnavailable");
                break;
            case AVAudioSessionRouteChangeReasonCategoryChange:
                // It turns out that we see this notification (at least in iOS 9.2)
                // when making a switch from a BT device to e.g. Speaker using the
                // iOS Control Center and that we therefore must check if the sample
                // rate has changed. And if so is the case, restart the audio unit.
                NSLog(@" CategoryChange");
                //NSLog(@" New category:%s" ,GetAudioSessionCategory().c_str());
                break;
            case AVAudioSessionRouteChangeReasonOverride:
                NSLog(@" Override");
                break;
            case AVAudioSessionRouteChangeReasonWakeFromSleep:
                NSLog(@" WakeFromSleep");
                break;
            case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
                NSLog(@" NoSuitableRouteForCategory");
                break;
            case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
                // The set of input and output ports has not changed, but their
                // configuration has, e.g., a port’s selected data source has
                // changed. Ignore this type of route change since we are focusing
                // on detecting headset changes.
                NSLog(@" RouteConfigurationChange (ignored)");
                valid_route_change = false;
                break;
        }
        
        if (valid_route_change) {
            // Log previous route configuration.
            AVAudioSessionRouteDescription* prev_route =
            notification.userInfo[AVAudioSessionRouteChangePreviousRouteKey];
            NSLog(@"Previous route:");
            //NSLog(@"%s",StdStringFromNSString(
            //                                  [NSString stringWithFormat:@"%@", prev_route]).c_str());
        }
    };
    
    // Get the default notification center of the current process.
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    
    // Add AVAudioSessionInterruptionNotification observer.
    id interruption_observer =
    [center addObserverForName:AVAudioSessionInterruptionNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:interrupt_block];
    // Add AVAudioSessionRouteChangeNotification observer.
    id route_change_observer =
    [center addObserverForName:AVAudioSessionRouteChangeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:route_change_block];
    
    // Increment refcount on observers using ARC bridge. Instance variable is a
    // void* instead of an id because header is included in other pure C++
    // files.
    audio_interruption_observer_ = (__bridge_retained void*)interruption_observer;
    route_change_observer_ = (__bridge_retained void*)route_change_observer;
}

void AudioDeviceIos::UnregisterNotificationObservers() {
    NSLog(@"UnregisterNotificationObservers");
    // Transfer ownership of observer back to ARC, which will deallocate the
    // observer once it exits this scope.
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    if (audio_interruption_observer_ != nullptr) {
        id observer = (__bridge_transfer id)audio_interruption_observer_;
        [center removeObserver:observer];
        audio_interruption_observer_ = nullptr;
    }
    if (route_change_observer_ != nullptr) {
        id observer = (__bridge_transfer id)route_change_observer_;
        [center removeObserver:observer];
        route_change_observer_ = nullptr;
    }
}

void AudioDeviceIos::SetupAudioBuffersForActiveAudioSession()
{
    NSLog(@"SetupAudioBuffersForActiveAudioSession");
    // Verify the current values once the audio session has been activated.
    RTCAudioSession* session = [RTCAudioSession sharedInstance];
    NSLog(@" sample rate: %f" ,session.sampleRate);
    NSLog(@" IO buffer duration: %f" , session.IOBufferDuration);
    NSLog(@" output channels: %ld" , session.outputNumberOfChannels);
    NSLog(@" input channels: %ld" , session.inputNumberOfChannels);
    NSLog(@" output latency: %f" , session.outputLatency);
    NSLog(@" input latency: %f" , session.inputLatency);
    
    // Log a warning message for the case when we are unable to set the preferred
    // hardware sample rate but continue and use the non-ideal sample rate after
    // reinitializing the audio parameters. Most BT headsets only support 8kHz or
    // 16kHz.
    if (session.sampleRate != sample_rate_) {
        NSLog(@"Unable to set the preferred sample rate");
    }
    //sample_rate_=session.sampleRate;
    
    // Allocate AudioBuffers to be used as storage for the received audio.
    // The AudioBufferList structure works as a placeholder for the
    // AudioBuffer structure, which holds a pointer to the actual data buffer
    // in |record_audio_buffer_|. Recorded audio will be rendered into this memory
    // at each input callback when calling AudioUnitRender().
    size_t sample_per_frame=static_cast<size_t>(session.session.sampleRate * session.IOBufferDuration + 0.5);
    const size_t data_byte_size = sample_per_frame*channel_*2; // 只支持16位采样精度
    record_audio_buffer_.reset(new SInt8[data_byte_size]);
    audio_record_buffer_list_.mNumberBuffers = 1;
    AudioBuffer* audio_buffer = &audio_record_buffer_list_.mBuffers[0];
    audio_buffer->mNumberChannels = channel_;
    audio_buffer->mDataByteSize = (UInt32)data_byte_size;
    audio_buffer->mData = record_audio_buffer_.get();
    
}

bool AudioDeviceIos::SetupAndInitializeVoiceProcessingAudioUnit()
{
    NSLog(@"SetupAndInitializeVoiceProcessingAudioUnit");
    assert(!vpio_unit_);
    // Create an audio component description to identify the Voice-Processing
    // I/O audio unit.
    AudioComponentDescription vpio_unit_description;
    vpio_unit_description.componentType = kAudioUnitType_Output;
    vpio_unit_description.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    vpio_unit_description.componentManufacturer = kAudioUnitManufacturer_Apple;
    vpio_unit_description.componentFlags = 0;
    vpio_unit_description.componentFlagsMask = 0;
    
    // Obtain an audio unit instance given the description.
    AudioComponent found_vpio_unit_ref =
    AudioComponentFindNext(nullptr, &vpio_unit_description);
    
    // Create a Voice-Processing IO audio unit.
    OSStatus result = noErr;
    result = AudioComponentInstanceNew(found_vpio_unit_ref, &vpio_unit_);
    if (result != noErr) {
        vpio_unit_ = nullptr;
        NSLog(@"AudioComponentInstanceNew failed: %d",result);
        return false;
    }
    
    // A VP I/O unit's bus 1 connects to input hardware (microphone). Enable
    // input on the input scope of the input element.
    AudioUnitElement input_bus = 1;
    UInt32 enable_input = 1;
    result = AudioUnitSetProperty(vpio_unit_, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input, input_bus, &enable_input,
                                  sizeof(enable_input));
    if (result != noErr) {
        DisposeAudioUnit();
        NSLog(@"Failed to enable input on input scope of input element: %d",result);
        return false;
    }
    
    // A VP I/O unit's bus 0 connects to output hardware (speaker). Enable
    // output on the output scope of the output element.
    AudioUnitElement output_bus = 0;
    UInt32 enable_output = 1;
    result = AudioUnitSetProperty(vpio_unit_, kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output, output_bus,
                                  &enable_output, sizeof(enable_output));
    if (result != noErr) {
        DisposeAudioUnit();
        NSLog(@"Failed to enable output on output scope of output element: %d",result);
        return false;
    }
    
    // Set the application formats for input and output:
    // - use same format in both directions
    // - avoid resampling in the I/O unit by using the hardware sample rate
    // - linear PCM => noncompressed audio data format with one frame per packet
    // - no need to specify interleaving since only mono is supported
    AudioStreamBasicDescription application_format = {0};
    UInt32 size = sizeof(application_format);
    application_format.mSampleRate = 8000;
    application_format.mFormatID = kAudioFormatLinearPCM;
    application_format.mFormatFlags =
    kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    application_format.mBytesPerPacket = kBytesPerSample;
    application_format.mFramesPerPacket = 1;  // uncompressed
    application_format.mBytesPerFrame = kBytesPerSample;
    application_format.mChannelsPerFrame = kPreferredNumberOfChannels;
    application_format.mBitsPerChannel = 8 * kBytesPerSample;
    // Store the new format.
    application_format_ = application_format;

    // Set the application format on the output scope of the input element/bus.
    result = AudioUnitSetProperty(vpio_unit_, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output, input_bus,
                                  &application_format, size);
    if (result != noErr) {
        DisposeAudioUnit();
        NSLog(@"Failed to set application format on output scope of input bus: %d",result);
        return false;
    }
    
    // Set the application format on the input scope of the output element/bus.
    result = AudioUnitSetProperty(vpio_unit_, kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input, output_bus,
                                  &application_format, size);
    if (result != noErr) {
        DisposeAudioUnit();
        NSLog(@"Failed to set application format on input scope of output bus: %d",result);
        return false;
    }
    
    // Specify the callback function that provides audio samples to the audio
    // unit.
    AURenderCallbackStruct render_callback;
    render_callback.inputProc = GetPlayoutData;
    render_callback.inputProcRefCon = this;
    result = AudioUnitSetProperty(
                                  vpio_unit_, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
                                  output_bus, &render_callback, sizeof(render_callback));
    if (result != noErr) {
        DisposeAudioUnit();
        NSLog(@"Failed to specify the render callback on the output bus: %d",result);
        return false;
    }
    
    // Disable AU buffer allocation for the recorder, we allocate our own.
    // TODO(henrika): not sure that it actually saves resource to make this call.
    UInt32 flag = 0;
    result = AudioUnitSetProperty(
                                  vpio_unit_, kAudioUnitProperty_ShouldAllocateBuffer,
                                  kAudioUnitScope_Output, input_bus, &flag, sizeof(flag));
    if (result != noErr) {
        DisposeAudioUnit();
        NSLog(@"Failed to disable buffer allocation on the input bus: %d",result);
    }
    
    // Specify the callback to be called by the I/O thread to us when input audio
    // is available. The recorded samples can then be obtained by calling the
    // AudioUnitRender() method.
    AURenderCallbackStruct input_callback;
    input_callback.inputProc = RecordedDataIsAvailable;
    input_callback.inputProcRefCon = this;
    result = AudioUnitSetProperty(vpio_unit_,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global, input_bus,
                                  &input_callback, sizeof(input_callback));
    if (result != noErr) {
        DisposeAudioUnit();
        NSLog(@"Failed to specify the input callback on the input bus: %d",result);
    }
    
    // Initialize the Voice-Processing I/O unit instance.
    // Calls to AudioUnitInitialize() can fail if called back-to-back on
    // different ADM instances. The error message in this case is -66635 which is
    // undocumented. Tests have shown that calling AudioUnitInitialize a second
    // time, after a short sleep, avoids this issue.
    // See webrtc:5166 for details.
    int failed_initalize_attempts = 0;
    result = AudioUnitInitialize(vpio_unit_);
    while (result != noErr) {
        NSLog(@"Failed to initialize the Voice-Processing I/O unit: %d",result);
        ++failed_initalize_attempts;
        if (failed_initalize_attempts == kMaxNumberOfAudioUnitInitializeAttempts) {
            // Max number of initialization attempts exceeded, hence abort.
            NSLog(@"Too many initialization attempts");
            DisposeAudioUnit();
            return false;
        }
        NSLog(@"pause 100ms and try audio unit initialization again...");
        [NSThread sleepForTimeInterval:0.1f];
        result = AudioUnitInitialize(vpio_unit_);
    }
    NSLog(@"Voice-Processing I/O unit is now initialized");
    return true;
}

void AudioDeviceIos::DisposeAudioUnit() {
    if (nullptr == vpio_unit_)
        return;
    OSStatus result = AudioComponentInstanceDispose(vpio_unit_);
    if (result != noErr) {
        NSLog(@"AudioComponentInstanceDispose failed:%d",result);
    }
    vpio_unit_ = nullptr;
}

OSStatus AudioDeviceIos::GetPlayoutData(void* in_ref_con,
                               AudioUnitRenderActionFlags* io_action_flags,
                               const AudioTimeStamp* time_stamp,
                               UInt32 in_bus_number,
                               UInt32 in_number_frames,
                               AudioBufferList* io_data)
{
    AudioDeviceIos* audio_device_ios = static_cast<AudioDeviceIos*>(in_ref_con);
    return audio_device_ios->OnGetPlayoutData(io_action_flags, in_number_frames,
                                              io_data);
}

OSStatus AudioDeviceIos::OnGetPlayoutData(
                                          AudioUnitRenderActionFlags* io_action_flags,
                                          UInt32 in_number_frames,
                                          AudioBufferList* io_data) {
    
    OSStatus result = noErr;
    // Get pointer to internal audio buffer to which new audio data shall be
    // written.
    const UInt32 dataSizeInBytes = io_data->mBuffers[0].mDataByteSize;
    SInt8* destination = static_cast<SInt8*>(io_data->mBuffers[0].mData);
    // Produce silence and give audio unit a hint about it if playout is not
    // activated.
    if (!playing_.load()) {
        *io_action_flags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(destination, 0, dataSizeInBytes);
        return noErr;
    }

    int ret=pcm_play_cb_((short*)destination,dataSizeInBytes/2,channel_);
    if(ret<=0)
    {
        *io_action_flags |= kAudioUnitRenderAction_OutputIsSilence;
        memset(destination, 0, dataSizeInBytes);
    }
    return result;
}

OSStatus AudioDeviceIos::RecordedDataIsAvailable(
                                                 void* in_ref_con,
                                                 AudioUnitRenderActionFlags* io_action_flags,
                                                 const AudioTimeStamp* in_time_stamp,
                                                 UInt32 in_bus_number,
                                                 UInt32 in_number_frames,
                                                 AudioBufferList* io_data) {

    AudioDeviceIos* audio_device_ios = static_cast<AudioDeviceIos*>(in_ref_con);
    return audio_device_ios->OnRecordedDataIsAvailable(
                                                       io_action_flags, in_time_stamp, in_bus_number, in_number_frames);
}

OSStatus AudioDeviceIos::OnRecordedDataIsAvailable(
                                   AudioUnitRenderActionFlags* io_action_flags,
                                   const AudioTimeStamp* in_time_stamp,
                                   UInt32 in_bus_number,
                                   UInt32 in_number_frames)
{
    OSStatus result = noErr;
    // Simply return if recording is not enabled.
    if (!recording_.load())
        return result;
    // Obtain the recorded audio samples by initiating a rendering cycle.
    // Since it happens on the input bus, the |io_data| parameter is a reference
    // to the preallocated audio buffer list that the audio unit renders into.
    // TODO(henrika): should error handling be improved?
    AudioBufferList* io_data = &audio_record_buffer_list_;
    result = AudioUnitRender(vpio_unit_, io_action_flags, in_time_stamp,
                             in_bus_number, in_number_frames, io_data);
    if (result != noErr) {
        NSLog(@"AudioUnitRender failed: %d" , result);
        return result;
    }
    // Get a pointer to the recorded audio and send it to the WebRTC ADB.
    // Use the FineAudioBuffer instance to convert between native buffer size
    // and the 10ms buffer size used by WebRTC.
    const UInt32 data_size_in_bytes = io_data->mBuffers[0].mDataByteSize;
    SInt8* data = static_cast<SInt8*>(io_data->mBuffers[0].mData);
    
    int sample_frame=data_size_in_bytes/2;
    AudioPacket* audioPkt=new AudioPacket();
    audioPkt->buffer=new short[sample_frame];
    memcpy(audioPkt->buffer, data, data_size_in_bytes);
    audioPkt->size=sample_frame;
    pcm_record_cb_(audioPkt);
    
    if(DEBUG_MIC_AUDIO)
    {
        mic_to_wav_->WriteSamples((const int16_t*)data, sample_frame);
    }
    
    return noErr;
}
