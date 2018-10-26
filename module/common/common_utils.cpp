#include "common_utils.h"

int add8K1ChannelAacAdtsHeard(char* buf,int rawDataSize)
{
    if(buf==nullptr)
        return -1;

    int adtsLength = 7;
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 11;  //8KHz
    int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    int fullLength = adtsLength + rawDataSize;
    // fill in ADTS data
    buf[0] = (char)0xFF; // 11111111     = syncword
    buf[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    buf[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    buf[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    buf[4] = (char)((fullLength&0x7FF) >> 3);
    buf[5] = (char)(((fullLength&7)<<5) + 0x1F);
    buf[6] = (char)0xFC;

    return 1;
}
