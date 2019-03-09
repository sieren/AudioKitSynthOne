//
//  S1NoteState.mm
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 3/06/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

#import <AudioKit/AudioKit-swift.h>
#include <AudioToolbox/AudioToolbox.h>
#include <AVFoundation/AVFoundation.h>
#include <libkern/OSAtomic.h>
#include <mach/mach_time.h>

#include <iostream>
#include <mach/mach_time.h>

#include "S1Arpegiator.hpp"
#include "S1Sequencer.hpp"
#import "AEArray.h"
#import "S1ArpModes.hpp"
#import "S1AudioUnit.h"

#define INVALID_BEAT_TIME DBL_MIN
#define INVALID_BPM DBL_MIN

static OSSpinLock lock;

/*
 * Pull data from the main thread to the audio thread if lock can be
 * obtained. Otherwise, just use the local copy of the data.
 */
static void pullEngineData(ABLLinkData* linkData, ABLEngineData* output) {
    // Always reset the signaling members to their default state
    output->resetToBeatTime = INVALID_BEAT_TIME;
    output->proposeBpm = INVALID_BPM;
    output->requestStart = NO;
    output->requestStop = NO;
    
    // Attempt to grab the lock guarding the shared engine data but
    // don't block if we can't get it.
    if (OSSpinLockTry(&lock)) {
        // Copy non-signaling members to the local thread cache
        linkData->localEngineData.outputLatency =
        linkData->sharedEngineData.outputLatency;
        linkData->localEngineData.quantum = linkData->sharedEngineData.quantum;
        
        // Copy signaling members directly to the output and reset
        output->resetToBeatTime = linkData->sharedEngineData.resetToBeatTime;
        linkData->sharedEngineData.resetToBeatTime = INVALID_BEAT_TIME;
        
        output->requestStart = linkData->sharedEngineData.requestStart;
        linkData->sharedEngineData.requestStart = NO;
        
        output->requestStop = linkData->sharedEngineData.requestStop;
        linkData->sharedEngineData.requestStop = NO;
        
        output->proposeBpm = linkData->sharedEngineData.proposeBpm;
        linkData->sharedEngineData.proposeBpm = INVALID_BPM;
        
        OSSpinLockUnlock(&lock);
    }
    
    // Copy from the thread local copy to the output. This happens
    // whether or not we were able to grab the lock.
    output->outputLatency = linkData->localEngineData.outputLatency;
    output->quantum = linkData->localEngineData.quantum;
}


S1Sequencer::S1Sequencer(KeyOnCallback keyOnCb,
    KeyOffCallback keyOffCb, BeatCounterChangedCallback beatChangedCb) :
    mTurnOnKey(keyOnCb),
    mTurnOffKey(keyOffCb),
    mBeatCounterDidChange(beatChangedCb)
    {}

void S1Sequencer::init() {
    previousHeldNoteNumbersAECount = 0;
    reserveNotes();
}

void S1Sequencer::reset(bool resetNotes) {
    previousHeldNoteNumbersAECount = resetNotes ? 0 : previousHeldNoteNumbersAECount;
    sequencerLastNotes.clear();
    sequencerNotes.clear();
    sequencerNotes2.clear();
}

ABLRenderData S1Sequencer::prepareProcess(AUAudioFrameCount frameCount, AUAudioFrameCount bufferOffset,
                   AEArray *heldNoteNumbersAE, DSPParameters &params)
{
    const int heldNoteNumbersAECount = heldNoteNumbersAE.count;
    const BOOL firstTimeAnyKeysHeld = (previousHeldNoteNumbersAECount == 0 && heldNoteNumbersAECount > 0);
    const BOOL firstTimeNoKeysHeld = (heldNoteNumbersAECount == 0 && previousHeldNoteNumbersAECount > 0);

    const BOOL arpSeqIsOn = (params[arpIsOn] == 1.f);
    // std::cout << ABLLinkBeatAtTime(renderData.sessionState, hostTime, 4) << std::endl;
    // reset arp/seq when user goes from 0 to N, or N to 0 held keys
    if ( arpSeqIsOn && (firstTimeNoKeysHeld || firstTimeAnyKeysHeld) ) {
        
        arpTime = 0;
        arpSampleCounter = 0;
        arpBeatCounter = 0;
        // Turn OFF previous beat's notes
        for (std::list<int>::iterator arpLastNotesIterator = sequencerLastNotes.begin(); arpLastNotesIterator != sequencerLastNotes.end(); ++arpLastNotesIterator) {
            mTurnOffKey(*arpLastNotesIterator);
        }
        sequencerLastNotes.clear();
        
        mBeatCounterDidChange();
    }
 //   if (mLinkData == nil) { return ABLRenderData{};}
    // Get a copy of the current link session state.
    const ABLLinkSessionStateRef sessionState = ABLLinkCaptureAudioSessionState(mLinkData->linkRef);
    
    // Get a copy of relevant engine parameters.
    ABLEngineData engineData;
    pullEngineData(mLinkData, &engineData);
    
    // The mHostTime member of the timestamp represents the time at
    // which the buffer is delivered to the audio hardware. The output
    // latency is the time from when the buffer is delivered to the
    // audio hardware to when the beginning of the buffer starts
    // reaching the output. We add those values to get the host time
    // at which the first sample of this buffer will reach the output.
    const auto hostTime = mach_absolute_time();
    const UInt64 hostTimeAtBufferBegin =
      hostTime + engineData.outputLatency;
    
    if (engineData.requestStart && !ABLLinkIsPlaying(sessionState)) {
        // Request starting playback at the beginning of this buffer.
        ABLLinkSetIsPlaying(sessionState, YES, hostTimeAtBufferBegin);
    }
    
    if (engineData.requestStop && ABLLinkIsPlaying(sessionState)) {
        // Request stopping playback at the beginning of this buffer.
        ABLLinkSetIsPlaying(sessionState, NO, hostTimeAtBufferBegin);
    }
    
    if (!mLinkData->isPlaying && ABLLinkIsPlaying(sessionState)) {
        // Reset the session state's beat timeline so that the requested
        // beat time corresponds to the time the transport will start playing.
        // The returned beat time is the actual beat time mapped to the time
        // playback will start, which therefore may be less than the requested
        // beat time by up to a quantum.
        ABLLinkRequestBeatAtStartPlayingTime(sessionState, 0., engineData.quantum);
        mLinkData->isPlaying = true;
    }
    else if(mLinkData->isPlaying && !ABLLinkIsPlaying(sessionState)) {
        mLinkData->isPlaying = false;
    }
    
    // Handle a tempo proposal
    if (engineData.proposeBpm != INVALID_BPM) {
        // Propose that the new tempo takes effect at the beginning of
        // this buffer.
        ABLLinkSetTempo(sessionState, engineData.proposeBpm, hostTimeAtBufferBegin);
    }
    
    ABLLinkCommitAudioSessionState(mLinkData->linkRef, sessionState);

    const Float64 hostTicksPerSample = mLinkData->secondsToHostTime / mLinkData->sampleRate;
    return ABLRenderData{hostTimeAtBufferBegin, sessionState, hostTimeAtBufferBegin,
        mLinkData->secondsToHostTime, hostTicksPerSample};
}

void S1Sequencer::process(DSPParameters &params, AEArray *heldNoteNumbersAE,
                          AUAudioFrameCount frameIndex, ABLRenderData renderData) {
    /// MARK: ARPEGGIATOR + SEQUENCER BEGIN
    const int heldNoteNumbersAECount = heldNoteNumbersAE.count;
    const BOOL arpSeqIsOn = (params[arpIsOn] == 1.f);
    const UInt64 hostTime = renderData.beginHostTime + llround(frameIndex * renderData.hostTicksPerSample);
    const UInt64 lastSampleHostTime = hostTime - llround(renderData.hostTicksPerSample);
    const BOOL firstTimeAnyKeysHeld = (previousHeldNoteNumbersAECount == 0 && heldNoteNumbersAECount > 0);

    
    // If arp is ON, or if previous beat's notes need to be turned OFF
    if ( arpSeqIsOn || sequencerLastNotes.size() > 0 ) {

        // Compare previous arpTime to current to see if we crossed a beat boundary
        const double tempo = params[arpRate];
        const double secPerBeat = 60.f * params[arpSeqTempoMultiplier] / params[arpRate];
        const double r0 = fmod(arpTime, secPerBeat);
        arpTime = arpSampleCounter / mSampleRate;
        arpTime = ABLLinkBeatAtTime(renderData.sessionState, hostTime, 1) / tempo; //arpSampleCounter/mSampleRate;
        const auto newBeatTime = beatTime + (params[arpRate] / 60.f) / mSampleRate;
        if (static_cast<int>(newBeatTime) > static_cast<int>(beatTime)) {
            std::cout << "Beat Advanced to: " << newBeatTime << " with arpRate: " << params[arpRate] << std::endl;
        }
        beatTime = newBeatTime;
        const double r1 = fmod(arpTime, secPerBeat);
        arpSampleCounter += 1.f;
        
        // If keys are now held, or if beat boundary was crossed
        if ( firstTimeAnyKeysHeld || r1 < r0 ) {
            
            // Turn off previous beat's notes even if arp is off
            for (std::list<int>::iterator arpLastNotesIterator = sequencerLastNotes.begin(); arpLastNotesIterator != sequencerLastNotes.end(); ++arpLastNotesIterator) {
                mTurnOffKey(*arpLastNotesIterator);
            }
            sequencerLastNotes.clear();
            
            // ARP/SEQ is ON
            if (arpSeqIsOn) {
                
                // Held Notes
                if (heldNoteNumbersAECount > 0) {
                    // Create Arp/Seq array based on held notes and/or sequence parameters
                    sequencerNotes.clear();
                    sequencerNotes2.clear();
                    
                    // Only update "notes per octave" when beat counter changes so sequencerNotes and sequencerLastNotes match
                    notesPerOctave = (int)AKPolyphonicNode.tuningTable.npo;
                    if (notesPerOctave <= 0) notesPerOctave = 12;
                    const float npof = (float)notesPerOctave/12.f; // 12ET ==> npof = 1
                    
                    if ( params[arpIsSequencer] == 1.f ) {
                        
                        // SEQUENCER
                        const int numSteps = params[arpTotalSteps] > 16 ? 16 : (int)params[arpTotalSteps];
                        for(int i = 0; i < numSteps; i++) {
                            const float onOff = params[(S1Parameter)(i + sequencerNoteOn00)];
                            const int octBoost = params[(S1Parameter)(i + sequencerOctBoost00)];
                            const int nn = params[(S1Parameter)(i + sequencerPattern00)] * npof;
                            const int nnob = (nn < 0) ? (nn - octBoost * notesPerOctave) : (nn + octBoost * notesPerOctave);
                            struct SeqNoteNumber snn;
                            snn.init(nnob, onOff);
                            sequencerNotes.push_back(snn);
                        }
                    } else {
                        
                        // ARPEGGIATOR
                        AEArrayEnumeratePointers(heldNoteNumbersAE, NoteNumber *, note) {
                            std::vector<NoteNumber>::iterator it = sequencerNotes2.begin();
                            sequencerNotes2.insert(it, *note);
                        }
                        const int heldNotesCount = (int)sequencerNotes2.size();
                        const int arpIntervalUp = params[arpInterval] * npof;
                        const int arpOctaves = (int)params[arpOctave] + 1;
                        const auto arpMode = static_cast<ArpegiatorMode>(params[arpDirection]);

                        switch(arpMode) {
                            case ArpegiatorMode::Up: {
                                Arpegiator::up(sequencerNotes, sequencerNotes2, heldNotesCount, arpOctaves,
                                               arpIntervalUp);
                                break;
                            }
                            case ArpegiatorMode::UpDown: {
                                int index = Arpegiator::up(sequencerNotes, sequencerNotes2, heldNotesCount,
                                                           arpOctaves, arpIntervalUp);
                                const bool noTail = true;
                                Arpegiator::down(sequencerNotes, sequencerNotes2, heldNotesCount, arpOctaves,
                                                 arpIntervalUp, noTail, index);
                                break;
                            }
                            case ArpegiatorMode::Down: {
                                Arpegiator::down(sequencerNotes, sequencerNotes2, heldNotesCount, arpOctaves,
                                                 arpIntervalUp, false);
                                break;
                            }
                        }
                    }
                    
                    // At least one key is held down, and a non-empty sequence has been created
                    if ( sequencerNotes.size() > 0 ) {
                        
                        // Advance arp/seq beatCounter, notify delegates
                        const int seqNotePosition = arpBeatCounter % sequencerNotes.size();
                        ++arpBeatCounter;
                        mBeatCounterDidChange();
                        
                        //MARK: ARP+SEQ: turn ON the note of the sequence
                        SeqNoteNumber& snn = sequencerNotes[seqNotePosition];
                        
                        if (params[arpIsSequencer] == 1.f) {
                            
                            // SEQUENCER
                            if (snn.onOff == 1) {
                                AEArrayEnumeratePointers(heldNoteNumbersAE, NoteNumber *, noteStruct) {
                                    const int baseNote = noteStruct->noteNumber;
                                    const int note = baseNote + snn.noteNumber;
                                    if (note >= 0 && note < S1_NUM_MIDI_NOTES) {
                                        mTurnOnKey(note, 127); //TODO: Add ARP/SEQ Velocity
                                        sequencerLastNotes.push_back(note);
                                    }
                                }
                            }
                        } else {
                            
                            // ARPEGGIATOR
                            const int note = snn.noteNumber;
                            if (note >= 0 && note < S1_NUM_MIDI_NOTES) {
                                mTurnOnKey(note, 127); //TODO: Add ARP/SEQ velocity
                                sequencerLastNotes.push_back(note);
                            }
                        }
                    }
                }
            }
        }
    }
    previousHeldNoteNumbersAECount = heldNoteNumbersAECount;
    
    /// MARK: ARPEGGIATOR + SEQUENCER END
}

void S1Sequencer::reserveNotes() {
    sequencerNotes.reserve(maxSequencerNotes);
    sequencerNotes2.reserve(maxSequencerNotes);
    sequencerLastNotes.resize(maxSequencerNotes);
}

/// MARK: End LINK


// Getter and Setter

int S1Sequencer::getArpBeatCount() {
    return arpBeatCounter;
}

void S1Sequencer::setLinkData(ABLLinkData* linkData) {
    mLinkData = linkData;
}

void S1Sequencer::setSampleRate(double sampleRate) {
    mSampleRate = sampleRate;
}
