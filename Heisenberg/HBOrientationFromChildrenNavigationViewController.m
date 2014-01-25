//
//  HBOrientationFromChildrenNavigationViewController.m
//  Heisenberg
//
//  Created by Dan Spinosa on 1/25/14.
//  Copyright (c) 2014 Dan Spinosa. All rights reserved.
//

#import "HBOrientationFromChildrenNavigationViewController.h"

@interface HBOrientationFromChildrenNavigationViewController ()

@end

@implementation HBOrientationFromChildrenNavigationViewController

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
	// Do any additional setup after loading the view.
}

-(NSUInteger)supportedInterfaceOrientations
{
    return [self.topViewController supportedInterfaceOrientations];
}

-(BOOL)shouldAutorotate
{
    return [self.topViewController shouldAutorotate];
}

@end
