//
//  SupplementaryButton.swift
//  ChattoAdditions
//
//  Created by Bespalov Vsevolod on 30/08/2019.
//

import UIKit

public class SupplementaryButton {
    
    public var icon: UIImage{
        didSet {
            setIconHandler?(icon)
        }
    }
    public let tapHandler: (() -> ())?
    public var isShowing: Bool = true {
        didSet {
            isShowingHandler?(isShowing)
        }
    }
    
    public init(icon: UIImage, tapHandler: (() -> ())?) {
        self.icon = icon
        self.tapHandler = tapHandler
    }
    
    var setIconHandler: ((UIImage) -> ())?
    var isShowingHandler: ((Bool) -> ())?
}
