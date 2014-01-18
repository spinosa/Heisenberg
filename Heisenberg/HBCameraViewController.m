//
//  HBCameraViewController.m
//  Heisenberg
//
//  Created by Dan Spinosa on 1/11/14.
//  Copyright (c) 2014 Dan Spinosa. All rights reserved.
//

#import "HBCameraViewController.h"
#import <GPUImage.h>
#import "HBEditImageViewController.h"

static NSString *kEditImageSegueIdentifier = @"EditImage";

@interface HBCameraViewController ()
@property (weak, nonatomic) IBOutlet UIView *cameraPreviewView;

@end

@implementation HBCameraViewController {
    //filtered input
    GPUImageStillCamera *_stillCamera;
    GPUImageFilter *_curFilter, *_unprocessedFilter;
    GPUImageView *_filteredVideoView;
    UIImage *_unprocessedImage;
    
    //face detection
    AVCaptureMetadataOutput *_metadataOutput;
    NSMutableDictionary *_onscreenFaceViews;
    
    //face detection metadata transforms
    CGFloat _xScale, _xOffset, _yScale, _yOffset, _widthScale, _heightScale;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	_onscreenFaceViews = [NSMutableDictionary new];

    // 1) Final output view
    _filteredVideoView = [[GPUImageView alloc] initWithFrame:self.cameraPreviewView.bounds];
    _filteredVideoView.fillMode = kGPUImageFillModePreserveAspectRatio;
    
    [self.cameraPreviewView addSubview:_filteredVideoView];
    _filteredVideoView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cameraPreviewView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"|[preview]|" options:0 metrics:nil views:@{@"preview":_filteredVideoView}]];
    [self.cameraPreviewView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[preview]|" options:0 metrics:nil views:@{@"preview":_filteredVideoView}]];
    
    // 2) Setup the camera input
    _stillCamera = [[GPUImageStillCamera alloc] init];
    _stillCamera.outputImageOrientation = self.interfaceOrientation;
    [self setupFaceDetection];

    // 3) No-filter image pipeline
    _unprocessedFilter = [[GPUImageCropFilter alloc] initWithCropRegion:CGRectMake(0, 0, 1.0, 1.0)];
    [_stillCamera addTarget:_unprocessedFilter];
    [_stillCamera startCameraCapture];
    
    // 4) initial filter
    [self setCameraPreviewFilter:[[GPUImageToonFilter alloc] init]];
//    [self setCameraPreviewFilter:[[GPUImageCropFilter alloc] initWithCropRegion:CGRectMake(0, 0, 1.0, 1.0)]];
}

- (void)viewDidAppear:(BOOL)animated
{
    // 5) face detection metadata preparedness
    [self updateMetadataTransform];
}

- (void)setCameraPreviewFilter:(GPUImageFilter *)newFilter
{
    if (_curFilter) {
        [_stillCamera pauseCameraCapture];
        [_curFilter removeAllTargets];
        [_stillCamera removeTarget:_curFilter];
    }
    
    // OPTIMIZE: we can -forceProcessingAtSize: or -forceProcessingAtSizeRespectingAspectRatio for the filter view
    // see https://github.com/BradLarson/GPUImage/issues/751
    // but it's not a simple drop in... the resulting processed image has to play with our aspect
    // ratio calculations throughout the app
    _curFilter = newFilter;
    [_stillCamera addTarget:_curFilter];
    [_curFilter addTarget:_filteredVideoView];

    [_stillCamera resumeCameraCapture];
}

- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                                duration:(NSTimeInterval)duration {
    _stillCamera.outputImageOrientation = toInterfaceOrientation;
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
    [self updateMetadataTransform];
}

#pragma mark Face Detection Shit
//see WWDC 2013 session 610

- (void)setupFaceDetection
{
    AVCaptureSession *session = [_stillCamera captureSession];
    
    _metadataOutput = [AVCaptureMetadataOutput new];
    if (![session canAddOutput:_metadataOutput]) {
        //TODO: BUG OUT!
        _metadataOutput = nil;
        return;
    }
    
    // Metadata processing will be fast, and mostly updating UI which should be done on the main thread
	// So just use the main dispatch queue instead of creating a separate one
	[_metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
	[session addOutput:_metadataOutput];
	
	if ( ![_metadataOutput.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeFace] ) {
		// face detection isn't supported via AV Foundation
        //TODO: BUG OUT!
		[self teardownAVFoundationFaceDetection];
		return;
	}
    
	_metadataOutput.metadataObjectTypes = @[AVMetadataObjectTypeFace];
	[self updateAVFoundationFaceDetection];
}

- (void)updateAVFoundationFaceDetection
{
	if (_metadataOutput){
		[[_metadataOutput connectionWithMediaType:AVMediaTypeMetadata] setEnabled:YES];
    }
}

- (void)teardownAVFoundationFaceDetection
{
	if (_metadataOutput){
		[[_stillCamera captureSession] removeOutput:_metadataOutput];
    }
	_metadataOutput = nil;
    for (UIView *fv in _onscreenFaceViews) {
        [fv removeFromSuperview];
    }
}

#pragma mark AVCaptureMetadataOutputObjectsDelegate

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)faces fromConnection:(AVCaptureConnection *)connection
{
    //faces are assigned unique (never reused) IDs while in view
    NSMutableSet* unseen = [NSMutableSet setWithArray:_onscreenFaceViews.allKeys];
	NSMutableSet* seen = [NSMutableSet setWithCapacity:faces.count];
    
    // Explicitly begin display updates, disabling implicity actions
    // This is from the WWDC sample code, not sure why it's needed/a good idea
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];
    
    // 1) move, or add new, faces
    for (AVMetadataFaceObject *face in faces) {
        NSNumber *faceID = @(face.faceID);
        [unseen removeObject:faceID];
        [seen addObject:faceID];
        
        //TODO: use some real views with hats and glasses!
        UIView *faceView = _onscreenFaceViews[faceID];
        if (!faceView) {
            faceView = ({
                UIView *v = [UIView new];
                v.layer.cornerRadius = 3.0f;
                v.layer.borderWidth = 2.0f;
                v.layer.borderColor = [UIColor redColor].CGColor;
                v;
            });
            _onscreenFaceViews[faceID] = faceView;
            [_filteredVideoView addSubview:faceView];
        }
     
        //The AVMetadataFaceObject is relative to the raw camera input.
        //We're not using a standard AVCaptureVideoPreviewLayer, need to replicate the functionality of
        // -transformedMetadataObjectForMetadataObject: to transform the raw metadata and make it relative
        // to our preview view...
        CGRect adjustedFaceBounds;// = [self adjustedFrameFor:face];
        CGFloat adjustedYaw, adjustedRoll;
        [self forFace:face transformedBounds:&adjustedFaceBounds yaw:&adjustedYaw roll:&adjustedRoll];
        
        //TODO: take yaw + roll into account when drawing actual hats
        faceView.frame = adjustedFaceBounds;
    }
    
    // 2) remove faces not detected
    for (NSNumber *unseenFaceID in unseen) {
        UIView *faceView = _onscreenFaceViews[unseenFaceID];
        [faceView removeFromSuperview];
        [_onscreenFaceViews removeObjectForKey:unseenFaceID];
    }
    
    [CATransaction commit];
}

#pragma mark Target-Action

- (IBAction)captureImageTapped:(UIButton *)sender {

    //TODO: next line for faster image capture; must reset to capture again
//    [_unprocessedFilter prepareForImageCapture];
    [_stillCamera capturePhotoAsImageProcessedUpToFilter:_unprocessedFilter withCompletionHandler:^(UIImage *processedImage, NSError *error) {
        if (!error) {
            _unprocessedImage = processedImage;
            [self performSegueWithIdentifier:kEditImageSegueIdentifier sender:self];
        } else {
            //TODO
        }
    }];
}

#pragma mark Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:kEditImageSegueIdentifier]) {
        HBEditImageViewController *editVC = (HBEditImageViewController *)segue.destinationViewController;
        editVC.unprocessedImage = _unprocessedImage;
    } else {
        //not expecting this
    }
}

#pragma mark - Metadata Transform Maths

- (void)forFace:(AVMetadataFaceObject *)face transformedBounds:(CGRect *)bounds yaw:(CGFloat *)yaw roll:(CGFloat *)roll
{
    *bounds = [self adjustedFrameFor:face];
    
    //TODO: adjust YAW + ROLL
}

- (CGRect)adjustedFrameFor:(AVMetadataFaceObject *)faceObject
{
    CGRect faceBounds = faceObject.bounds;
    
    //TODO: make this generic, instead of just handling the back camera in portrait
    
    // 1) adjust bounds for input settings
    // portrait/rear cam/flipped => rotate 90deg CW + flip the bounding box horizontally
    faceBounds = CGRectMake((1.0-faceBounds.origin.y) - faceBounds.size.height,
                            faceBounds.origin.x,
                            faceBounds.size.height,
                            faceBounds.size.width);
    
    return CGRectMake((faceBounds.origin.x * _xScale) + _xOffset,
                      (faceBounds.origin.y * _yScale) + _yOffset,
                      faceBounds.size.width * _widthScale,
                      faceBounds.size.height * _heightScale);
    
    //OPTIMIZE: wrap all this into one precomputed matrix multiplication
}

//this must be called when view changes size, device rotates, or camera changes
- (void)updateMetadataTransform
{
    CGFloat widthScaling, heightScaling;
    CGSize currentViewSize = _filteredVideoView.bounds.size;
    CGRect insetRect = AVMakeRectWithAspectRatioInsideRect(_filteredVideoView.inputImageSize, _filteredVideoView.bounds);
    
    switch(_filteredVideoView.fillMode)
    {
        case kGPUImageFillModeStretch:
        {
            widthScaling = 1.0;
            heightScaling = 1.0;
            
            _xScale = currentViewSize.width * widthScaling;
            _xOffset = 0;
            _yScale = currentViewSize.height * heightScaling;
            _yOffset = 0;
            _widthScale = insetRect.size.width * widthScaling;
            _heightScale = insetRect.size.height * heightScaling;
        }; break;
        case kGPUImageFillModePreserveAspectRatio:
        {
            widthScaling = insetRect.size.width / currentViewSize.width;
            heightScaling = insetRect.size.height / currentViewSize.height;
            
            _xScale = currentViewSize.width * widthScaling;
            _xOffset = insetRect.origin.x;
            _yScale = currentViewSize.height * heightScaling;
            _yOffset = insetRect.origin.y;
            _widthScale = insetRect.size.width * widthScaling;
            _heightScale = insetRect.size.height * heightScaling;
        }; break;
        case kGPUImageFillModePreserveAspectRatioAndFill:
        {
            widthScaling = currentViewSize.height / insetRect.size.height;
            heightScaling = currentViewSize.width / insetRect.size.width;
            
            _xScale = currentViewSize.width * widthScaling;
            _xOffset = -(_xScale-currentViewSize.width)/2.f;
            _yScale = currentViewSize.height * heightScaling;
            _yOffset = -(_yScale-currentViewSize.height)/2.f;
            _widthScale = insetRect.size.width * widthScaling;
            _heightScale = insetRect.size.height * heightScaling;
        }; break;
    }
}

@end
