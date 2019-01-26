//
//  AudioUnitViewController.swift
//  SynthOneAU
//
//  Created by Marcus W. Hobbs on 1/25/19.
//  Copyright © 2019 AudioKit. All rights reserved.
//

import CoreAudioKit
import AudioKit
import AVFoundation

class Global {
    static var conductor: Conductor {
        get {
            AKLog("Warning, using wrong Conductor")
            return _conductor
        }
    }
    static var _conductor = Conductor()
}

public class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: SynthOneAUv3AudioUnit?

    override public func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let segueID = segue.identifier

        if segueID == "LoadUI" || segueID == "LoadUI2" {
            let parent: Manager = segue.destination as! Manager

            parent.conductor = (audioUnit?.conductor)!

        }
    }
    public override func viewDidLoad() {
        super.viewDidLoad()

        if audioUnit == nil {
            return
        }

        // Get the parameter tree and add observers for any parameters that the UI needs to keep in sync with the AudioUnit
    }

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        audioUnit = try SynthOneAUv3AudioUnit(componentDescription: componentDescription, options: [])

        DispatchQueue.main.async {
            self.performSegue(withIdentifier: "LoadUI", sender: self)
        }

        return audioUnit!
    }

}

