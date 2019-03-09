//
//  S1LinkData.h
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 3/06/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

#import "ABLLink.h"

typedef struct {
    UInt32 outputLatency; // Hardware output latency in HostTime
    Float64 resetToBeatTime;
    bool requestStart;
    bool requestStop;
    Float64 proposeBpm;
    Float64 quantum;
} ABLEngineData;

/*
 * Structure that stores all data needed by the audio callback.
 */
typedef struct ABLLink* ABLLinkRef;

typedef struct {
    ABLLinkRef linkRef;
    // Shared between threads. Only write when engine not running.
    Float64 sampleRate;
    // Shared between threads. Only write when engine not running.
    Float64 secondsToHostTime;
    // Shared between threads. Written by the main thread and only
    // read by the audio thread when doing so will not block.
    ABLEngineData sharedEngineData;
    // Copy of sharedEngineData owned by audio thread.
    ABLEngineData localEngineData;
    // Owned by audio thread
    UInt64 timeAtLastClick;
    // Owned by audio thread
    bool isPlaying;
} ABLLinkData;

typedef struct {
    UInt64 hostTimeAtBufferBegin;
    ABLLinkSessionStateRef sessionState;
    UInt64 beginHostTime;
    Float64 secondsToHostTime;
    Float64 hostTicksPerSample;
} ABLRenderData;
