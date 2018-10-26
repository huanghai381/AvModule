//
//  media_packet.h
//  ss181_app
//
//  Created by iisfree on 2018/9/22.
//  Copyright © 2018年 huanghai. All rights reserved.
//

#ifndef media_packet_h
#define media_packet_h

//音频包与队列元素定义
typedef struct _AudioPacket {
    short * buffer;  //pcm buffer指针
    char*  data;    //编码后数据buffer指针
    int size;
    float position;

    _AudioPacket() {
        buffer = nullptr;
        data=nullptr;
        size = 0;
        position = -1;
    }
    ~_AudioPacket() {
        if (nullptr != buffer) {
            delete[] buffer;
            buffer = nullptr;
        }
        if (nullptr != data) {
            delete[] data;
            data = nullptr;
        }
    }
} AudioPacket;


typedef struct _AudioPacketList {
    AudioPacket *pkt;
    struct _AudioPacketList *next;
    _AudioPacketList(){
        pkt = nullptr;
        next = nullptr;
    }
} AudioPacketList;


#endif /* media_packet_h */
