/*
 The MIT License (MIT)
 
 Copyright (c) 2015-present Badoo Trading Limited.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */

import UIKit

public protocol ChatInputBarDelegate: class {
    func inputBarShouldBeginTextEditing(_ inputBar: ChatInputBar) -> Bool
    func inputBarDidBeginEditing(_ inputBar: ChatInputBar)
    func inputBarDidEndEditing(_ inputBar: ChatInputBar)
    func inputBarDidChangeText(_ inputBar: ChatInputBar)
    func inputBarSendButtonPressed(_ inputBar: ChatInputBar)
    func inputBar(_ inputBar: ChatInputBar, shouldFocusOnItem item: ChatInputItemProtocol) -> Bool
    func inputBar(_ inputBar: ChatInputBar, didReceiveFocusOnItem item: ChatInputItemProtocol)
    func inputBarDidShowPlaceholder(_ inputBar: ChatInputBar)
    func inputBarDidHidePlaceholder(_ inputBar: ChatInputBar)
}

public enum ChatSendButtonType {
    case normal, custom
}

@objc
open class ChatInputBar: ReusableXibView {
    
    public weak var delegate: ChatInputBarDelegate?
    weak var presenter: ChatInputBarPresenter?
    
    public var shouldEnableSendButton = { (inputBar: ChatInputBar) -> Bool in
        switch inputBar.sendButtonType {
        case .normal:
            return !inputBar.textView.text.isEmpty && inputBar.isSendingEnable
        case .custom:
            return true
        }
    }
    
    public var sendButtonType: ChatSendButtonType = .normal
    
    public var isSendingEnable: Bool = true {
        didSet {
            updateSendButton()
        }
    }
    public var handleInputManually: Bool = true
    public var isTopDescriptionHidden: Bool = true {
        didSet {
            descriptionLabelHeightConstraint.isActive = !isTopDescriptionHidden
            descriptionLableHiddenConstraint.isActive = isTopDescriptionHidden
            self.layoutIfNeeded()
        }
    }
    public var topDescriptionText: String {
        set {
            topDescriptionLabel.text = newValue
        }
        get {
            return topDescriptionLabel.text ?? ""
        }
    }
    
    var charactersCountLabelMinVisibilityCount: Int = 0
    var charactersCountLabelColorsRanges: [NSRange: UIColor]?
    
    @IBOutlet weak var scrollView: HorizontalStackScrollView!
    @IBOutlet weak var textView: ExpandableTextView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var textBorderView: UIView!
    @IBOutlet weak var topDescriptionLabel: UILabel!
    @IBOutlet weak var charactersCountLabel: UILabel!
    @IBOutlet weak var topBorderHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var descriptionLableHiddenConstraint: NSLayoutConstraint!
    @IBOutlet weak var descriptionLabelHeightConstraint: NSLayoutConstraint!
    @IBOutlet var constraintsForHiddenTextView: [NSLayoutConstraint]!
    @IBOutlet var tabBarContainerHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var settingsButtonImageView: UIImageView!
    
    @IBOutlet weak var supplementaryButtonsStackView: UIStackView!
    
    @IBOutlet weak var sendButtonTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var sendButtonLeftConstraint: NSLayoutConstraint!
    @IBOutlet weak var sendButtonRightConstraint: NSLayoutConstraint!
    @IBOutlet weak var sendButtonWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var sendButtonHeightConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var textViewContainerTopConstraint: NSLayoutConstraint!
    @IBOutlet weak var textViewContainerLeftConstraint: NSLayoutConstraint!
    @IBOutlet weak var textViewContainerBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var textViewContainerRightConstraint: NSLayoutConstraint!
    @IBOutlet weak var settingsButtonContainerWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var settingsButtonImageViewWidthConstraint: NSLayoutConstraint!
    
    fileprivate var settingsButtonTapHandler: (() -> ())?
    fileprivate var textFieldButtonTapHandler: (() -> ())?
    private var supplementaryButtonsMap: [UIButton: SupplementaryButton] = [:]
    
    class open func loadNib() -> ChatInputBar {
        let view = Bundle(for: self).loadNibNamed(self.nibName(), owner: nil, options: nil)!.first as! ChatInputBar
        view.translatesAutoresizingMaskIntoConstraints = false
        view.frame = CGRect.zero
        return view
    }
    
    override class func nibName() -> String {
        return "ChatInputBar"
    }
    
    open override func awakeFromNib() {
        super.awakeFromNib()
        self.textView.scrollsToTop = false
        self.textView.delegate = self
        self.textView.placeholderDelegate = self
        self.scrollView.scrollsToTop = false
        self.sendButton.isEnabled = false
    }
    
    open var showsTextView: Bool = true {
        didSet {
            self.setNeedsUpdateConstraints()
            self.setNeedsLayout()
            self.updateIntrinsicContentSizeAnimated()
        }
    }
    
    public var maxCharactersCount: UInt? // nil -> unlimited
    
    private func updateIntrinsicContentSizeAnimated() {
        let options: UIViewAnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
        UIView.animate(withDuration: 0.25, delay: 0, options: options, animations: { () -> Void in
            self.invalidateIntrinsicContentSize()
            self.layoutIfNeeded()
            self.superview?.layoutIfNeeded()
        }, completion: nil)
    }
    
    open override func layoutSubviews() {
        self.updateConstraints() // Interface rotation or size class changes will reset constraints as defined in interface builder -> constraintsForVisibleTextView will be activated
        super.layoutSubviews()
        updateTextViewExclusionPaths()
    }
    
    var inputItems = [ChatInputItemProtocol]() {
        didSet {
            let inputItemViews = self.inputItems.map { (item: ChatInputItemProtocol) -> ChatInputItemView in
                let inputItemView = ChatInputItemView()
                inputItemView.inputItem = item
                inputItemView.delegate = self
                return inputItemView
            }
            self.scrollView.addArrangedViews(inputItemViews)
        }
    }
    
    open func becomeFirstResponderWithInputView(_ inputView: UIView?) {
        self.textView.inputView = inputView
        
        if self.textView.isFirstResponder {
            self.textView.reloadInputViews()
        } else {
            self.textView.becomeFirstResponder()
        }
    }
    
    public var inputText: String {
        get {
            return self.textView.text
        }
        set {
            self.textView.text = newValue
            self.updateSendButton()
        }
    }
    
    public var inputSelectedRange: NSRange {
        get {
            return self.textView.selectedRange
        }
        set {
            self.textView.selectedRange = newValue
        }
    }
    
    public var placeholderText: String {
        get {
            return self.textView.placeholderText
        }
        set {
            self.textView.placeholderText = newValue
        }
    }
    
    fileprivate func updateSendButton() {
        self.sendButton.isEnabled = self.shouldEnableSendButton(self)
    }
    
    fileprivate func updateCharactersCountLabel(_ count: Int) {
        guard let colorsRanges = charactersCountLabelColorsRanges else {
            return
        }
        if count >= charactersCountLabelMinVisibilityCount {
            charactersCountLabel.isHidden = false
            charactersCountLabel.text = String(count)
        } else {
            charactersCountLabel.isHidden = true
            return
        }
        for (range, color) in colorsRanges {
            if range.contains(count) {
                self.charactersCountLabel.textColor = color
            }
        }
    }
    
    @IBAction func buttonTapped(_ sender: AnyObject) {
        if !handleInputManually {
            self.presenter?.onSendButtonPressed()
        }
        self.delegate?.inputBarSendButtonPressed(self)
    }
    
    public func setTextViewPlaceholderAccessibilityIdentifer(_ accessibilityIdentifer: String) {
        self.textView.setTextPlaceholderAccessibilityIdentifier(accessibilityIdentifer)
    }
    
    public func setSendButtonIcons(_ icons: [UIControlStateWrapper: UIImage]) {
        icons.forEach { (state, icon) in
            self.sendButton.setBackgroundImage(icon, for: state.controlState)
        }
    }
    
    public func setLoading(_ isLoading: Bool) {
        if isLoading {
            sendButton.isHidden = true
            activityIndicator.isHidden = false
            activityIndicator.startAnimating()
        } else {
            sendButton.isHidden = false
            activityIndicator.stopAnimating()
        }
    }
    
    public func focusOnTextField() {
        textView.becomeFirstResponder()
    }
    
    private func updateTextViewExclusionPaths() {
        let correction: CGFloat = 5.0
        let supButtonContainerRect: CGRect = supplementaryButtonsStackView.bounds
        let excludedRect = CGRect(
            x: textView.textContainer.size.width - supButtonContainerRect.width - correction,
            y: 0,
            width: supButtonContainerRect.width + correction,
            height: supButtonContainerRect.height/2 - correction
        )
        let exclusionBezierPath = UIBezierPath(rect: excludedRect)
        textView.textContainer.exclusionPaths = [exclusionBezierPath]
    }
}

// MARK: - ChatInputItemViewDelegate
extension ChatInputBar: ChatInputItemViewDelegate {
    func inputItemViewTapped(_ view: ChatInputItemView) {
        self.focusOnInputItem(view.inputItem)
    }
    
    public func focusOnInputItem(_ inputItem: ChatInputItemProtocol) {
        let shouldFocus = self.delegate?.inputBar(self, shouldFocusOnItem: inputItem) ?? true
        guard shouldFocus else { return }
        
        self.presenter?.onDidReceiveFocusOnItem(inputItem)
        self.delegate?.inputBar(self, didReceiveFocusOnItem: inputItem)
    }
}

// MARK: - ChatInputBarAppearance
extension ChatInputBar {
    public func setAppearance(_ appearance: ChatInputBarAppearance) {
        self.textView.font = appearance.textInputAppearance.font
        self.textView.textColor = appearance.textInputAppearance.textColor
        self.textView.tintColor = appearance.textInputAppearance.tintColor
        self.textView.textContainerInset = appearance.textInputAppearance.textInsets
        self.textView.setTextPlaceholderFont(appearance.textInputAppearance.placeholderFont)
        self.textView.setTextPlaceholderColor(appearance.textInputAppearance.placeholderColor)
        self.textView.placeholderText = appearance.textInputAppearance.placeholderText
        self.textView.backgroundColor = appearance.textInputAppearance.backgroundColor
        self.textView.keyboardAppearance = appearance.textInputAppearance.keyboardAppearance
        self.textBorderView.layer.borderColor = appearance.textInputAppearance.borderColor.cgColor
        self.textBorderView.layer.borderWidth = appearance.textInputAppearance.borderWidth
        self.textBorderView.layer.cornerRadius = appearance.textInputAppearance.borderRadius
        self.textBorderView.layer.masksToBounds = true
        
        self.tabBarInterItemSpacing = appearance.tabBarAppearance.interItemSpacing
        self.tabBarContentInsets = appearance.tabBarAppearance.contentInsets
        
        self.sendButton.contentEdgeInsets = appearance.sendButtonAppearance.insets
        self.sendButtonTopConstraint.constant = appearance.sendButtonAppearance.buttonOffsets.top
        self.sendButtonLeftConstraint.constant = appearance.sendButtonAppearance.buttonOffsets.left
        self.sendButtonRightConstraint.constant = appearance.sendButtonAppearance.buttonOffsets.right
        self.sendButtonWidthConstraint.constant = appearance.sendButtonAppearance.buttonSize.width
        self.sendButtonHeightConstraint.constant = appearance.sendButtonAppearance.buttonSize.height
        if let buttonIcons = appearance.sendButtonAppearance.buttonIcons {
            buttonIcons.forEach { (state, icon) in
                self.sendButton.setBackgroundImage(icon, for: state.controlState)
            }
        } else {
            self.sendButton.setTitle(appearance.sendButtonAppearance.title, for: .normal)
            appearance.sendButtonAppearance.titleColors.forEach { (state, color) in
                self.sendButton.setTitleColor(color, for: state.controlState)
            }
            self.sendButton.titleLabel?.font = appearance.sendButtonAppearance.font
        }
        self.tabBarContainerHeightConstraint.constant = appearance.tabBarAppearance.height
        
        self.textViewContainerTopConstraint.constant = appearance.textInputAppearance.textContainerInsets.top
        self.textViewContainerLeftConstraint.constant = appearance.textInputAppearance.textContainerInsets.left
        self.textViewContainerBottomConstraint.constant = appearance.textInputAppearance.textContainerInsets.bottom
        self.textViewContainerRightConstraint.constant = appearance.textInputAppearance.textContainerInsets.right
        
        self.topBorderHeightConstraint.constant = appearance.textInputAppearance.topHeight
        self.topDescriptionLabel.font = appearance.textInputAppearance.topDescriptionTextFont
        self.topDescriptionLabel.textColor = appearance.textInputAppearance.topDescriptionTextColor
        
        self.charactersCountLabel.font = appearance.textInputAppearance.charactersCountTextFont
        self.charactersCountLabel.isHidden = !appearance.textInputAppearance.isCharactersCountTextVisible
        
        self.charactersCountLabelMinVisibilityCount = appearance.textInputAppearance.charactersCountTextMinVisibilityCount
        self.charactersCountLabelColorsRanges = appearance.textInputAppearance.charactersCountTextColorsRanges
        
        if appearance.settingsButtonAppearance.isShowing,
            let icon: UIImage = appearance.settingsButtonAppearance.icon,
            let tapHandler: () -> () = appearance.settingsButtonAppearance.tapHandler {
            settingsButtonContainerWidthConstraint.constant = 32.0
            settingsButtonImageViewWidthConstraint.constant = 16.0
            
            settingsButtonTapHandler = tapHandler
            settingsButton.setImage(icon, for: .normal)
            settingsButton.addTarget(self, action: #selector(settingsButtonTap), for: .touchUpInside)
        }
        
        for supplementaryButton in appearance.textInputAppearance.supplementaryButtons {
            let button = UIButton(frame: CGRect.zero)
            button.setImage(supplementaryButton.icon, for: .normal)
            supplementaryButton.setIconHandler = { [weak button] (icon: UIImage) in
                button?.setImage(icon, for: .normal)
            }
            supplementaryButton.isShowingHandler = { [weak button] (isShowing: Bool) in
                button?.isHidden = !isShowing
            }
            button.addTarget(self, action: #selector(supplementaryButtonTap(_:)), for: .touchUpInside)
            supplementaryButtonsMap[button] = supplementaryButton
            supplementaryButtonsStackView.addArrangedSubview(button)
        }
        supplementaryButtonsStackView.sizeToFit()
        
        
    }
    
    @objc
    private func settingsButtonTap() {
        settingsButtonTapHandler?()
    }
    
    @objc
    private func supplementaryButtonTap(_ sender: UIButton) {
        if let supButton: SupplementaryButton = supplementaryButtonsMap[sender] {
            supButton.tapHandler?()
        }
    }
}

extension ChatInputBar { // Tabar
    public var tabBarInterItemSpacing: CGFloat {
        get {
            return self.scrollView.interItemSpacing
        }
        set {
            self.scrollView.interItemSpacing = newValue
        }
    }
    
    public var tabBarContentInsets: UIEdgeInsets {
        get {
            return self.scrollView.contentInset
        }
        set {
            self.scrollView.contentInset = newValue
        }
    }
}

// MARK: UITextViewDelegate
extension ChatInputBar: UITextViewDelegate {
    public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        return self.delegate?.inputBarShouldBeginTextEditing(self) ?? true
    }
    
    public func textViewDidEndEditing(_ textView: UITextView) {
        self.presenter?.onDidEndEditing()
        self.delegate?.inputBarDidEndEditing(self)
    }
    
    public func textViewDidBeginEditing(_ textView: UITextView) {
        self.presenter?.onDidBeginEditing()
        self.delegate?.inputBarDidBeginEditing(self)
    }
    
    public func textViewDidChange(_ textView: UITextView) {
        self.delegate?.inputBarDidChangeText(self)
        self.updateSendButton()
        self.updateCharactersCountLabel(textView.text.count)
    }
    
    public func textView(_ textView: UITextView, shouldChangeTextIn nsRange: NSRange, replacementText text: String) -> Bool {
        let range = self.textView.text.bma_rangeFromNSRange(nsRange)
        if let maxCharactersCount = self.maxCharactersCount {
            let currentCount = textView.text.count
            let rangeLength = textView.text[range].count
            let nextCount = currentCount - rangeLength + text.count
            return UInt(nextCount) <= maxCharactersCount
        }
        return true
    }
}

// MARK: ExpandableTextViewPlaceholderDelegate
extension ChatInputBar: ExpandableTextViewPlaceholderDelegate {
    public func expandableTextViewDidShowPlaceholder(_ textView: ExpandableTextView) {
        self.delegate?.inputBarDidShowPlaceholder(self)
    }
    
    public func expandableTextViewDidHidePlaceholder(_ textView: ExpandableTextView) {
        self.delegate?.inputBarDidHidePlaceholder(self)
    }
}

private extension String {
    func bma_rangeFromNSRange(_ nsRange: NSRange) -> Range<String.Index> {
        guard
            let from16 = utf16.index(utf16.startIndex, offsetBy: nsRange.location, limitedBy: utf16.endIndex),
            let to16 = utf16.index(from16, offsetBy: nsRange.length, limitedBy: utf16.endIndex),
            let from = String.Index(from16, within: self),
            let to = String.Index(to16, within: self)
            else { return  self.startIndex..<self.startIndex }
        return from ..< to
    }
}
