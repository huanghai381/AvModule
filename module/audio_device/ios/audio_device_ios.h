#ifndef AUDIO_DEVICE_IOS_H
#define AUDIO_DEVICE_IOS_H

#include <AudioUnit/AudioUnit.h>

#include <atomic>

#include "media/module/audio_device/audio_device.h"
#include "media/module/common/wav_file.h"

class AudioDeviceIos : public AudioDevice
{
public:
    AudioDeviceIos();   
     ~AudioDeviceIos();

    //override from AudioDevice
    void Init(int sample_rate,int channel) override;
    void InitPlayout(PcmPlayCb pcm_play_cb) override;
    void InitRecording(PcmRecordCb pcm_record_cb) override;
    int32_t StartPlayout() override;
    int32_t StopPlayout() override;
    int32_t StartRecording() override;
    int32_t StopRecording() override;
    int32_t SetLoudspeakerStatus(bool enable) override;
    void Destory() override;
    
private:
    bool InitPlayOrRecord();
    // Closes and deletes the voice-processing I/O unit.
    void ShutdownPlayOrRecord();
    bool ActivateAudioSession(bool activate);  //激活或者取消激活Audio Session
    void RegisterNotificationObservers();     //注册音频被打断与音频route改变回调
    void UnregisterNotificationObservers();
    void SetupAudioBuffersForActiveAudioSession();
    bool SetupAndInitializeVoiceProcessingAudioUnit();
    void DisposeAudioUnit();

    // Callback function called on a real-time priority I/O thread from the audio
    // unit. This method is used to provide audio samples to the audio unit.
    static OSStatus GetPlayoutData(void* in_ref_con,
                                   AudioUnitRenderActionFlags* io_action_flags,
                                   const AudioTimeStamp* time_stamp,
                                   UInt32 in_bus_number,
                                   UInt32 in_number_frames,
                                   AudioBufferList* io_data);
    OSStatus OnGetPlayoutData(AudioUnitRenderActionFlags* io_action_flags,
                              UInt32 in_number_frames,
                              AudioBufferList* io_data);
    
    // Callback function called on a real-time priority I/O thread from the audio
    // unit. This method is used to signal that recorded audio is available.
    static OSStatus RecordedDataIsAvailable(
                                            void* in_ref_con,
                                            AudioUnitRenderActionFlags* io_action_flags,
                                            const AudioTimeStamp* time_stamp,
                                            UInt32 in_bus_number,
                                            UInt32 in_number_frames,
                                            AudioBufferList* io_data);
    OSStatus OnRecordedDataIsAvailable(
                                       AudioUnitRenderActionFlags* io_action_flags,
                                       const AudioTimeStamp* time_stamp,
                                       UInt32 in_bus_number,
                                       UInt32 in_number_frames);

private:
    int sample_rate_;
    int channel_;
    PcmRecordCb pcm_record_cb_;
    PcmPlayCb   pcm_play_cb_;
    
    std::atomic<bool> recording_;
    std::atomic<bool> playing_;
    
    // Set to true after successful call to Init(), false otherwise.
    bool initialized_;
    
    // Set to true after successful call to InitRecording(), false otherwise.
    bool rec_is_initialized_;
    
    // Set to true after successful call to InitPlayout(), false otherwise.
    bool play_is_initialized_;
    
    // Audio interruption observer instance.
    void* audio_interruption_observer_;
    void* route_change_observer_;
    
    // Contains the audio data format specification for a stream of audio.
    AudioStreamBasicDescription application_format_;
    // Provides a mechanism for encapsulating one or more buffers of audio data.
    // Only used on the recording side.
    AudioBufferList audio_record_buffer_list_;
    // Temporary storage for recorded data. AudioUnitRender() renders into this
    // array as soon as a frame of the desired buffer size has been recorded.
    std::unique_ptr<SInt8[]> record_audio_buffer_;
    // The Voice-Processing I/O unit has the same characteristics as the
    // Remote I/O unit (supports full duplex low-latency audio input and output)
    // and adds AEC for for two-way duplex communication. It also adds AGC,
    // adjustment of voice-processing quality, and muting. Hence, ideal for
    // VoIP applications.
    AudioUnit vpio_unit_;
    
    //for debug
    webrtc::WavWriter* mic_to_wav_;
};

#endif // AUDIO_DEVICE_IOS_H
