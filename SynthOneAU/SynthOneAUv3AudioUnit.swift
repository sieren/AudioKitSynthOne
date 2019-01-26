//
//  DigitalD1AUv3AudioUnit.swift
//  DigitalD1AUv3
//
//  Created by Aurelius Prochazka on 9/16/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

import AVFoundation
import AudioKit
import CoreAudioKit
import AudioToolbox

class SynthOneAUv3AudioUnit: AUAudioUnit {
    private var _outputBusArray: AUAudioUnitBusArray!
    private var _internalRenderBlock: AUInternalRenderBlock!
    private var _parameterTree: AUParameterTree!
    var engine = AVAudioEngine()
    var conductor: Conductor!
    var currentTempo = 0.0
    var transportStateIsMoving = false
    var mcb: AUHostMusicalContextBlock?
    var tsb: AUHostTransportStateBlock?
    var moeb: AUMIDIOutputEventBlock?

//    override var factoryPresets: [AUAudioUnitPreset]? {
//        return conductor.auPresets
//    }
//
//    override var currentPreset: AUAudioUnitPreset? {
//
//        get {
//            print("getting \(conductor.currentAUPreset.number) \(conductor.currentAUPreset.name)")
//            return conductor.currentAUPreset
//
//        }
//        set(newValue) {
//            //            print("newValue \(newValue?.number) \(newValue?.name)")
//            conductor.currentAUPreset = newValue!
//            print("after \(conductor.currentAUPreset.number) \(conductor.currentAUPreset.name)")
//        }
//
//    }

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions) throws {
        AudioKit.engine = engine
        conductor = Conductor()

        do {
            try engine.enableManualRenderingMode(.realtime, format: AudioKit.format, maximumFrameCount: 4_096)
//            conductor.start()
            try super.init(componentDescription: componentDescription, options: options)
            let bus = try AUAudioUnitBus(format: AudioKit.format)
            self._outputBusArray = AUAudioUnitBusArray(audioUnit: self, busType: AUAudioUnitBusType.output, busses: [bus])
        } catch {
            throw error
        }

        let frequency = AUParameter(
            identifier: "frequency",
            name: "Frequency (Hz)",
            address: AKOscillatorParameter.frequency.rawValue,
            range: -12...12,
            unit: .hertz,
            flags: .default)
        _parameterTree = AUParameterTree(children: [frequency])
        _parameterTree.implementorValueObserver = { param, value in
//            self.conductor.core.sampler1.pitchBend = Double(value)
        }
        frequency.value = Float(AKOscillator.defaultFrequency)

        self._internalRenderBlock = { (actionFlags, timeStamp, frameCount, outputBusNumber, outputData, renderEvent, pullInputBlock) in

            if renderEvent != nil {
                let head: AURenderEventHeader = renderEvent!.pointee.head
                if head.eventType == .parameter {
                    //let parameter: AUParameterEvent = renderEvent!.pointee.parameter
                } else if head.eventType == .parameterRamp {
                    //let parameter: AUParameterEvent = renderEvent!.pointee.parameter
                } else if head.eventType == .MIDI {
                    var MIDI: AUMIDIEvent? = renderEvent?.pointee.MIDI
                    while MIDI != nil {
                        let data = MIDI!.data
                        if MIDI!.eventType == AURenderEventType.MIDI { // might be redundant?
                            let statusByte = data.0 >> 4
                            let channel = data.0 & 0b0000_1111
                            let data1 = data.1 & 0b0111_1111
                            let data2 = data.2 & 0b0111_1111
                            if statusByte == 0b1000 {
                                // note off
                                self.conductor.synth.stop(noteNumber: data1)
                            } else if statusByte == 0b1001 {
                                if data2 > 0 {
                                    // note on
                                    self.conductor.synth.play(noteNumber: data1, velocity: data2)
                                } else {
                                    // note off
                                    self.conductor.synth.stop(noteNumber: data1)
                                }
                            } else if statusByte == 0b1010 {
                                // poly key pressure
                                NSLog("channel:%d, poly key pressure nn:%d, p:%d", channel, data1, data2)
                            } else if statusByte == 0b1011 {
                                // controller change
                                NSLog("channel:%d, controller change cc:%d, value:%d", channel, data1, data2)
                            } else if statusByte == 0b1100 {
                                // program change
                                NSLog("channel:%d, program change preset #:%d", channel, data1)
                            } else if statusByte == 0b1101 {
                                // channel pressure
                                NSLog("channel:%d, channel pressure:%d", channel, data1)
                            } else if statusByte == 0b1110 {
                                // pitch bend
                                _ = UInt16(data2) << 7 + UInt16(data1)
                                //                                NSLog("channel:%d, pitch bend fine:%d, course:%d, pb:%d", channel, data1, data2, pb)
                                //                                conductor.pitchBend(channel: channel, amount: pb)
                            }
                        }
                        MIDI = MIDI!.next?.pointee.MIDI

                    }
                } else if head.eventType == .midiSysEx {
                    //let MIDI: AUMIDIEvent = renderEvent!.pointee.MIDI
                }
            }

            // AUHostMusicalContextBlock
            // Block by which hosts provide musical tempo, time signature, and beat position
            if let mcb = self.mcb {
                var timeSignatureNumerator = 0.0
                var timeSignatureDenominator = 0
                var currentBeatPosition = 0.0
                var sampleOffsetToNextBeat = 0
                var currentMeasureDownbeatPosition = 0.0

                if mcb( &self.currentTempo, &timeSignatureNumerator, &timeSignatureDenominator, &currentBeatPosition, &sampleOffsetToNextBeat, &currentMeasureDownbeatPosition ) {
//                    self.conductor.tempo = self.currentTempo
//                    self.conductor.hostTempo = self.currentTempo

                    //                    NSLog("current tempo %f", self.currentTempo)
                    //                    NSLog("timeSignatureNumerator %f", timeSignatureNumerator)
                    //                    NSLog("timeSignatureDenominator %ld", timeSignatureDenominator)

                    if self.transportStateIsMoving {
                        //                        NSLog("currentBeatPosition %f", currentBeatPosition);
                        //                        NSLog("sampleOffsetToNextBeat %ld", sampleOffsetToNextBeat);
                        //                        NSLog("currentMeasureDownbeatPosition %f", currentMeasureDownbeatPosition);
                    }
                }

            }

            // AUHostTransportStateBlock
            // Block by which hosts provide information about their transport state.
            if let tsb = self.tsb {
                var flags: AUHostTransportStateFlags = []
                var currentSamplePosition = 0.0
                var cycleStartBeatPosition = 0.0
                var cycleEndBeatPosition = 0.0

                if tsb(&flags, &currentSamplePosition, &cycleStartBeatPosition, &cycleEndBeatPosition) {

                    if flags.contains(AUHostTransportStateFlags.changed) {
                        //                        NSLog("AUHostTransportStateChanged bit set")
                        //                        NSLog("currentSamplePosition %f", currentSamplePosition)
                    }

                    if flags.contains(AUHostTransportStateFlags.moving) {
                        //                        NSLog("AUHostTransportStateMoving bit set");
                        //                        NSLog("currentSamplePosition %f", currentSamplePosition)

                        self.transportStateIsMoving = true

                    } else {
                        self.transportStateIsMoving = false
                    }

                    if flags.contains(AUHostTransportStateFlags.recording) {
                        //                        NSLog("AUHostTransportStateRecording bit set")
                        //                        NSLog("currentSamplePosition %f", currentSamplePosition)
                    }

                    if flags.contains(AUHostTransportStateFlags.cycling) {
                        //                        NSLog("AUHostTransportStateCycling bit set")
                        //                        NSLog("currentSamplePosition %f", currentSamplePosition)
                        //                        NSLog("cycleStartBeatPosition %f", cycleStartBeatPosition)
                        //                        NSLog("cycleEndBeatPosition %f", cycleEndBeatPosition)
                    }

                }
            }


            _ = self.engine.manualRenderingBlock(frameCount, outputData, nil)

            return noErr
        }
    }
    override func supportedViewConfigurations(_ availableViewConfigurations: [AUAudioUnitViewConfiguration]) -> IndexSet {
        for configuration in availableViewConfigurations {
            print("width ", configuration.width)
            print("height ", configuration.height)
            print("has controller ", configuration.hostHasController)
            print("")
        }
        return [0, 1] //0 = ipad, 1 = garageband, 2 = big ipad
    }

    override var parameterTree: AUParameterTree {
        return self._parameterTree
    }

    override var outputBusses: AUAudioUnitBusArray {
        return self._outputBusArray
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        return self._internalRenderBlock
    }
}
