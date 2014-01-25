//
//  HBFaceView.m
//  Heisenberg
//
//  Created by Dan Spinosa on 1/25/14.
//  Copyright (c) 2014 Dan Spinosa. All rights reserved.
//

#import "HBFaceView.h"

@interface HBFaceView()
@property (weak, nonatomic) IBOutlet UIView *holderView;
@property (weak, nonatomic) IBOutlet UIImageView *hat;
@property (weak, nonatomic) IBOutlet UIImageView *glasses;
@end

@implementation HBFaceView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

- (void)awakeFromNib
{
    /// --HAT--
    //center hat on face (see xib)
    //make hat same hight as face (see xib -- doesn't matter, aspect fit is bound by width for this image)
    //make hat wider than face (replace placholder from xib)
    [self.holderView addConstraint:[NSLayoutConstraint constraintWithItem:self.hat attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self.holderView attribute:NSLayoutAttributeWidth multiplier:1.75 constant:0]];
    //move hat up to top of head (replace placeholder from nib)
    [self.holderView addConstraint:[NSLayoutConstraint constraintWithItem:self.hat attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.holderView attribute:NSLayoutAttributeCenterY multiplier:-0.5 constant:0]];
    

    /// --GLASSES--
    //center glasses on face (see xib)
    //make glasses same height as face (see xib -- doesn't matter, aspect fit is bound by width for this image)
    //make glasses same width as face (see xib)
    //move glasses to eyeline (replace placeholder from nib)
    [self.holderView addConstraint:[NSLayoutConstraint constraintWithItem:self.glasses attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.holderView attribute:NSLayoutAttributeCenterY multiplier:.7 constant:0]];
}

@end
