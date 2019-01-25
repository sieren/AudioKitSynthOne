//
//  UpdatableViewController.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 7/25/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//

import UIKit

public class ConductorAwareViewController: UIViewController {
    var conductor: Conductor!
}

public class UpdatableViewController: ConductorAwareViewController {

    public override func viewDidLoad() {
        super.viewDidLoad()
        //TODO
//        conductor.viewControllers.insert(self)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        conductor.updateAllUI()
    }

    // subclasses should update UI elements that do not conform to S1Control protocol, should not call super
    func updateUI(_ parameter: S1Parameter, control inputControl: S1Control?, value: Double) {}
}

protocol AffectedByLink {
    func setupLinkStuff()
}

extension UpdatableViewController: AffectedByLink {
    @objc func setupLinkStuff() {
        // Do nothing by default
    }
}
