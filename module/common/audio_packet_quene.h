//
//  audio_packet_quene.hpp
//  ss181_app
//
//  Created by iisfree on 2018/9/22.
//  Copyright © 2018年 huanghai. All rights reserved.
//

#ifndef audio_packet_quene_h
#define audio_packet_quene_h

#include <stdio.h>
#include <pthread.h>

#include "media_packet.h"

class AudioPacketQuene
{
public:
    AudioPacketQuene();
    ~AudioPacketQuene();
    
    int put(AudioPacket* audioPacket);
    /* return < 0 if aborted, 0 if no packet and > 0 if packet.  */
    int get(AudioPacket **audioPacket, bool block);
    int size();
    void start();
    void stop();

    
private:
    void flush();
    
private:
    AudioPacketList* mFirst;
    AudioPacketList* mLast;
    int mNbPackets;
    bool mAbortRequest;
    pthread_mutex_t mutex_;
    pthread_cond_t cond_;
};


#endif /* audio_packet_quene_hpp */
