//
//  HBEditImageViewController.m
//  Heisenberg
//
//  Created by Dan Spinosa on 1/11/14.
//  Copyright (c) 2014 Dan Spinosa. All rights reserved.
//

#import "HBEditImageViewController.h"

@interface HBEditImageViewController ()

@property (weak, nonatomic) IBOutlet UIImageView *imageView;

@end

@implementation HBEditImageViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.imageView.image = self.unprocessedImage;
}

- (void)setUnprocessedImage:(UIImage *)unprocessedImage
{
    if (_unprocessedImage != unprocessedImage) {
        _unprocessedImage = unprocessedImage;
        self.imageView.image = _unprocessedImage;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
