//
//  Manager+DevView.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 5/25/18.
//  Copyright © 2018 AudioKit. All rights reserved.
//

extension Manager: AboutDelegate {

    func showDevView() {
        isDevView = false
        devPressed()
    }
}

// DevViewDelegate protocol functions

extension Manager: DevViewDelegate {

    func freezeArpRateChanged(_ value: Bool) {
        appSettings.freezeArpRate = value
        conductor.updateDisplayLabel("Freeze Arp Rate: \(value == false ? "false" : "true")")
    }

    func freezeReverbChanged(_ value: Bool) {
        appSettings.freezeReverb = value
        conductor.updateDisplayLabel("Freeze Reverb: \(value == false ? "false" : "true")")
    }

    func freezeDelayChanged(_ value: Bool) {
        appSettings.freezeDelay = value
        conductor.updateDisplayLabel("Freeze Delay: \(value == false ? "false" : "true")")
    }

    func freezeArpSeqChanged(_ value: Bool) {
        appSettings.freezeArpSeq = value
        conductor.updateDisplayLabel("Freeze Arp+Sequencer: \(value == false ? "false" : "true")")
    }

    func portamentoChanged(_ value: Double) {
        appSettings.portamentoHalfTime = value
        conductor.updateDisplayLabel("dsp smoothing half time: \(value.decimalString)")
    }
}
