//
//  audio_packet_quene.cpp
//  ss181_app
//
//  Created by iisfree on 2018/9/22.
//  Copyright © 2018年 huanghai. All rights reserved.
//

#include "audio_packet_quene.h"

AudioPacketQuene::AudioPacketQuene()
{
    pthread_mutex_init(&mutex_, nullptr);
    pthread_cond_init(&cond_, nullptr);
    mAbortRequest=true;
}

AudioPacketQuene::~AudioPacketQuene()
{
    stop();
    pthread_mutex_destroy(&mutex_);
    pthread_cond_destroy(&cond_);
}

int AudioPacketQuene::put(AudioPacket* audioPacket)
{
    if (mAbortRequest) {
        delete audioPacket;
        audioPacket=nullptr;
        return -1;
    }

    AudioPacketList *pkt1 = new AudioPacketList();
    if (!pkt1)
        return -1;
    pkt1->pkt = audioPacket;
    pkt1->next = nullptr;
    
    pthread_mutex_lock(&mutex_);
    if (mLast == nullptr) {
        mFirst = pkt1;
    } else {
        mLast->next = pkt1;
    }
    
    mLast = pkt1;
    mNbPackets++;

    pthread_mutex_unlock(&mutex_);
    pthread_cond_signal(&cond_);
    
    return 0;
}

int AudioPacketQuene::get(AudioPacket **audioPacket, bool block)
{
   AudioPacketList *pkt1;
    int ret;
    
    pthread_mutex_lock(&mutex_);
    for (;;) {
        if (mAbortRequest) {
            ret = -1;
            break;
        }
        
        pkt1 = mFirst;
        if (pkt1) {
            mFirst = pkt1->next;
            if (!mFirst)
                mLast = nullptr;
            mNbPackets--;
            *audioPacket = pkt1->pkt;
            delete pkt1;
            pkt1 = nullptr;
            ret = 1;
            break;
        } else if (!block) {
            ret = 0;
            break;
        } else {
            pthread_cond_wait(&cond_, &mutex_);
        }
    }
    pthread_mutex_unlock(&mutex_);
    return ret;
}

int AudioPacketQuene::size()
{
    pthread_mutex_lock(&mutex_);
    int size = mNbPackets;
    pthread_mutex_unlock(&mutex_);
    return size;
}

void AudioPacketQuene::start()
{
    pthread_mutex_lock(&mutex_);
    mAbortRequest = false;
    mNbPackets = 0;
    mFirst = nullptr;
    mLast = nullptr;
    pthread_mutex_unlock(&mutex_);
}

void AudioPacketQuene::stop()
{
    pthread_mutex_lock(&mutex_);
    mAbortRequest = true;
    pthread_mutex_unlock(&mutex_);
    pthread_cond_signal(&cond_);
    flush();
}

void AudioPacketQuene::flush()
{
    AudioPacketList *pkt, *pkt1;
    AudioPacket *audioPacket;
    
    pthread_mutex_lock(&mutex_);
    for (pkt = mFirst; pkt != nullptr; pkt = pkt1) {
        pkt1 = pkt->next;
        audioPacket = pkt->pkt;
        if(nullptr != audioPacket){
            delete audioPacket;
            audioPacket=nullptr;
        }
        delete pkt;
        pkt = nullptr;
    }
    mLast = nullptr;
    mFirst = nullptr;
    mNbPackets = 0;    
    pthread_mutex_unlock(&mutex_);
}
