//
//  VideoEditController.m
//  Xchangewithme
//
//  Created by Xin YingTai on 21/5/14.
//  Copyright (c) 2014 Xin YingTai. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

#import "VideoPickerController.h"
#import "VideoEditController.h"

#import "CustomTitleView.h"
#import "FilterView.h"

#import "SAVideoRangeSlider.h"
#import "GPUImage.h"
#import "MBProgressHUD.h"
#import "AppDelegate.h"

@interface VideoEditController () <SAVideoRangeSliderDelegate, FilterViewDelegate, GPUImageMovieDelegate>
{
    SAVideoRangeSlider *videoSlider;
    
    GPUImagePicture *picture;
    GPUImageMovie *movie;
    GPUImageMovieWriter *movieWriter;
    GPUImageView *imageView;
    GPUImageRotationMode rotationMode;
    GPUImageOutput<GPUImageInput> *filter;
    
    AVAudioPlayer *audioPlayer;
    
    AVAsset *asset;
    AVAssetImageGenerator *generator;
    
    bool drawing;
    bool exporting;
    bool playing;
}

@end

@implementation VideoEditController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
		
    }
    return self;
}

- (void)loadView
{
    [super loadView];
    
    // Navigation Bar;
    VideoPickerController *viewController = (VideoPickerController *)self.navigationController;
    
    switch (viewController.type) {
        case 1:
        case 4:
            self.title = @"Personal Info";
            break;
        case 2:
            self.title = @"Work Info";
            break;
        case 3:
            self.title = @"Entity Info";
            break;
        default:
            break;
    }
    
    [self.navigationController.navigationBar setBackgroundImage:nil forBarMetrics:UIBarMetricsDefault];
    
    self.navigationItem.hidesBackButton = YES;
    
    UIBarButtonItem *itemForDelete = [[UIBarButtonItem alloc] initWithCustomView:btnForDelete];
    self.navigationItem.leftBarButtonItem = itemForDelete;
    
    UIBarButtonItem *itemForApply = [[UIBarButtonItem alloc] initWithCustomView:btnForApply];
    self.navigationItem.rightBarButtonItem = itemForApply;
    
    // Video Slider;
    videoSlider = [[SAVideoRangeSlider alloc] initWithFrame:viewForRange.bounds videoUrl:self.videoURL];
    videoSlider.delegate = self;
    videoSlider.minGap = 2.0f;
    videoSlider.maxGap = 30.0f;
    [videoSlider setPopoverBubbleSize:30.0f height:30.0f];
    [viewForRange addSubview:videoSlider];
    
    // Filter View;
    FilterView *filterView = [FilterView sharedView];
    filterView.delegate = self;
    filterView.frame = viewForFilter.bounds;
    [viewForFilter addSubview:filterView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	
    // Image View;
    imageView = [[GPUImageView alloc] initWithFrame:viewForVideo.bounds];
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [viewForVideo addSubview:imageView];
	
    // Filter;
	[self setFilterType:FilterTypeOriginal];
    
    // Asset;
    asset = [[AVURLAsset alloc] initWithURL:self.videoURL options:nil];
    generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    
    AVAssetTrack *assetTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] objectAtIndex:0];
    CGAffineTransform tranform = assetTrack.preferredTransform;
    
    if (tranform.a == 1.0f && tranform.b == 0.0f && tranform.c == 0.0f && tranform.d == 1.0f) {
        rotationMode =  kGPUImageNoRotation;
    } else if (tranform.a == -1.0f && tranform.b == 0.0f && tranform.c == 0.0f && tranform.d == -1.0f) {
        rotationMode = kGPUImageRotate180;
    } else if (tranform.a == 0.f && tranform.b == -1.0f && tranform.c == 1.0 && tranform.d == 0.0f) {
        rotationMode =  kGPUImageRotateLeft;
    } else if (tranform.a == 0.0f && tranform.b == 1.0f && tranform.c == -1.0f && tranform.d == 0.0f) {
        rotationMode = kGPUImageRotateRight;
    }
    
    [self extractImage:0.0f];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)videoRange:(SAVideoRangeSlider *)videoRange didChangeLeftPosition:(CGFloat)leftPosition
{
    if (!playing) {
        [self extractImage:leftPosition];
    }
}

- (void)videoRange:(SAVideoRangeSlider *)videoRange didChangeRightPosition:(CGFloat)rightPosition
{
    if (!playing) {
        [self extractImage:rightPosition];
    }
}

- (void)videoRange:(SAVideoRangeSlider *)videoRange didChangeLeftPosition:(CGFloat)leftPosition rightPosition:(CGFloat)rightPosition
{
	
}

- (void)videoRange:(SAVideoRangeSlider *)videoRange didGestureStateEndedLeftPosition:(CGFloat)leftPosition rightPosition:(CGFloat)rightPosition
{
    
}

- (void)extractImage:(CGFloat)position
{
    if (drawing) {
        return;
    }
    
    drawing = YES;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        CMTime time = CMTimeMakeWithSeconds(position, asset.duration.timescale);
        CMTime actualTime;
        NSError *error = nil;
        CGImageRef image = [generator copyCGImageAtTime:time actualTime:&actualTime error:&error];
        UIImage *thumb = [[UIImage alloc] initWithCGImage:image];
        CGImageRelease(image);
        [self removeAllTargets];
        
        picture = [[GPUImagePicture alloc] initWithImage:thumb smoothlyScaleOutput:YES];
        [self applyFilter];
		
        drawing = NO;
    });
}

- (void)didSelectFilter:(NSNumber *)index
{
    if (!playing) {
        [videoSlider getMovieFrame:index];
        
        FilterType filterType = [index integerValue];
        
        [self removeAllTargets];
        
        [self setFilterType:filterType];
        [self applyFilter];
    }
}

- (void)setFilterType:(FilterType)filterType
{
    switch (filterType) {
        case FilterTypeBookStore:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"BookStore"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeCity:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"City"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeCountry:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"Country"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeFilm:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"Film"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeForest:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"Forest"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeLake:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"Lake"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeMoment:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"Moment"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeNYC:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"NYC"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeTea:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"Tea"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeVintage:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"Vintage"];
            GPUImageVignetteFilter *vintage = [[GPUImageVignetteFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:vintage];
            [tone addTarget:vintage];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:vintage];
            break;
        }
            
        case FilterType1Q84:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"1Q84"];
            GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:saturation];
            [tone addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation];
            break;
        }
            
        case FilterTypeBW:
        {
            filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageToneCurveFilter *tone = [[GPUImageToneCurveFilter alloc] initWithACV:@"B&W"];
            GPUImageGrayscaleFilter *gray = [[GPUImageGrayscaleFilter alloc] init];
            
            [(GPUImageFilterGroup *)filter addFilter:gray];
            [tone addTarget:gray];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:tone]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:gray];
            break;
        }
            
        default:
        {
            filter = [[GPUImageFilter alloc] init];
/*			filter = [[GPUImageFilterGroup alloc] init];
            
            // Tone Curve ;
            GPUImageGammaFilter *gammar = [[GPUImageGammaFilter alloc] init];
			GPUImageSaturationFilter *saturation = [[GPUImageSaturationFilter alloc] init];
            
			[(GPUImageFilterGroup *)filter addFilter:saturation];
            [gammar addTarget:saturation];
            
            [(GPUImageFilterGroup *)filter setInitialFilters:[NSArray arrayWithObject:gammar]];
            [(GPUImageFilterGroup *)filter setTerminalFilter:saturation]; */
            break;
        }
    }
}

- (void)removeAllTargets;
{
    [picture removeAllTargets];
    [filter removeAllTargets];
}

- (void)applyFilter
{
    [picture addTarget:filter];
    [filter addTarget:imageView];
    [picture processImage];
}

- (void)trim:(BOOL)exportFlag
{
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/trim.m4a"];
    unlink([path UTF8String]);
    NSURL *url = [NSURL fileURLWithPath:path];
    
    NSArray *presets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    
    if ([presets containsObject:AVAssetExportPresetMediumQuality]) {
        CMTime start = CMTimeMakeWithSeconds(videoSlider.leftPosition, asset.duration.timescale);
        CMTime duration = CMTimeMakeWithSeconds(videoSlider.rightPosition - videoSlider.leftPosition, asset.duration.timescale);
        CMTimeRange range = CMTimeRangeMake(start, duration);
		
        AVMutableComposition *composition = [AVMutableComposition composition];
        AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
        AVAssetTrack *assetTrack = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
        [audioTrack insertTimeRange:range ofTrack:assetTrack atTime:kCMTimeInvalid error:nil];
        
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetAppleM4A];
        exportSession.outputFileType = AVFileTypeAppleM4A;

        exportSession.outputURL = url;
        
        if (!exportFlag) {
            MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:[AppDelegate sharedDelegate].window animated:YES];
            [hud setLabelText:@"Loading..."];
        }
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            switch (exportSession.status) {
                case AVAssetExportSessionStatusFailed:
                case AVAssetExportSessionStatusCancelled:
                {
                    if (!exporting) {
                        
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
							[self mergeFailed];
                        });
                    }
                    break;
                }
                    
                default:
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
						[self trimVideo];
					});
                    break;
                }
            }
        }];
    }
}

- (void)trimVideo
{
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/trim.mp4"];
    unlink([path UTF8String]);
    NSURL *url = [NSURL fileURLWithPath:path];
    
    NSArray *presets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    
    if ([presets containsObject:AVAssetExportPresetMediumQuality]) {
        CMTime start = CMTimeMakeWithSeconds(videoSlider.leftPosition, asset.duration.timescale);
        CMTime duration = CMTimeMakeWithSeconds(videoSlider.rightPosition - videoSlider.leftPosition, asset.duration.timescale);
        CMTimeRange range = CMTimeRangeMake(start, duration);
		//llll
        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetHighestQuality];
        exportSession.outputFileType = AVFileTypeQuickTimeMovie;
//        AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetMediumQuality];
        exportSession.shouldOptimizeForNetworkUse = YES;
//        exportSession.outputFileType = AVFileTypeMPEG4;
        exportSession.outputURL = url;
        exportSession.timeRange = range;
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            switch (exportSession.status) {
                case AVAssetExportSessionStatusFailed:
                case AVAssetExportSessionStatusCancelled:
                {
                    if (!exporting) {
                        
                    } else {
                        dispatch_async(dispatch_get_main_queue(), ^{
							[self mergeFailed];
						});
                    }
                    break;
                }
                    
                default:
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        //[SVProgressHUD dismiss];
                        [MBProgressHUD hideHUDForView:[AppDelegate sharedDelegate].window animated:YES];
                        if (!exporting) {
                            [self play];
                        } else {
                            [self export];
                        }
					});
                    break;
                }
            }
        }];
    }
}

- (void)play
{
    // Audio;
    NSString *audioPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/trim.m4a"];
    NSURL *audioURL = [NSURL fileURLWithPath:audioPath];
    
    audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:audioURL error:nil];
    [audioPlayer setVolume:1.0f];
    [audioPlayer prepareToPlay];
    [audioPlayer play];
    
    // Video;
    NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/trim.mp4"];
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    
    [movie removeAllTargets];
    [filter removeAllTargets];
    
    movie = [[GPUImageMovie alloc] initWithURL:videoURL];
    movie.delegate = self;
    movie.playAtActualSpeed = YES;
    
    [movie addTarget:filter];
    [filter addTarget:imageView];
    [filter setInputRotation:rotationMode atIndex:0];
	
    [movie startProcessing];
    
    // Animation;
    CGRect frame = imgForTick.frame;
    int thumbWidth = ceil(videoSlider.frame_width*0.05) * 2;
    
    frame.origin.x = (videoSlider.leftPosition * videoSlider.frame_width / videoSlider.durationSeconds) + thumbWidth;
    imgForTick.frame = frame;
    imgForTick.hidden = NO;
    
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:videoSlider.rightPosition - videoSlider.leftPosition];
    frame.origin.x = (videoSlider.rightPosition * videoSlider.frame_width / videoSlider.durationSeconds) - thumbWidth;
    imgForTick.frame = frame;
    [UIView commitAnimations];
    
    playing = YES;
}

- (void)stop
{
    if (playing) {
        // Audio;
        [audioPlayer stop];
        
        // Video;
        [movie cancelProcessing];

        // Animation;
        [imgForTick.layer removeAllAnimations];
    }
}

- (void)export
{
    NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/trim.mp4"];
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];

    if ([filter class] == [GPUImageFilter class]) {
        NSString *filename = [NSString stringWithFormat:@"tmp/movie%ld.mp4", time(nil)];
        NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:filename];
        unlink([path UTF8String]);
        NSURL *url = [NSURL fileURLWithPath:path];
        
        [[NSFileManager defaultManager] copyItemAtPath:videoPath toPath:path error:nil];
        
        [self mergeSuccessed:url];
    } else {
        NSString *filterPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/filter.mp4"];
        unlink([filterPath UTF8String]);
        NSURL *filterURL = [NSURL fileURLWithPath:filterPath];
        
        [movie removeAllTargets];
        [filter removeAllTargets];
        
        movie = [[GPUImageMovie alloc] initWithURL:videoURL];
        movie.delegate = self;
        movie.playAtActualSpeed = NO;
        
        NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
        AVAssetTrack *track = [tracks lastObject];
        CGSize mediaSize = track.naturalSize;
        
        switch (rotationMode) {
            case kGPUImageNoRotation:
                break;
                
            case kGPUImageRotateLeft:
                mediaSize = CGSizeMake(mediaSize.height, mediaSize.width);
                break;
                
            case kGPUImageRotateRight:
                mediaSize = CGSizeMake(mediaSize.height, mediaSize.width);
                break;
                
            case kGPUImageRotate180:
                break;
                
            default:
                break;
        }
        
        movieWriter = [[GPUImageMovieWriter alloc] initWithMovieURL:filterURL size:mediaSize];
        movieWriter.shouldPassthroughAudio = YES;
        
        movie.audioEncodingTarget = movieWriter;
        
        [movie addTarget:filter];
        [filter addTarget:movieWriter];
        
        [movieWriter setInputRotation:rotationMode atIndex:0];
        
        [movieWriter startRecording];
        [movie startProcessing];
    }
}

- (void)didCompletePlayingMovie
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (playing) {
            // Audio;
            [audioPlayer stop];
            
            // Animation;
            [imgForTick.layer removeAllAnimations];
        }
        
        if (!exporting) {
            imgForTick.hidden = YES;
            btnForPlay.selected = NO;
        } else if (!playing) {
            [movieWriter finishRecording];
            [movie removeAllTargets];
            [filter removeAllTargets];
			
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1f * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[self merge];
			});
        }
        
        playing = NO;
    });
}

- (void)merge
{
    AVMutableComposition *composition = [AVMutableComposition composition];

    // Video;
    NSString *videoPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/filter.mp4"];
    NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
    
    AVAsset *videoAsset = [[AVURLAsset alloc] initWithURL:videoURL options:nil];
    CMTime duration = videoAsset.duration;
    AVAssetTrack *videoAssetTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    AVMutableCompositionTrack *videoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    
    [videoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:videoAssetTrack atTime:kCMTimeInvalid error:nil];

    // Audio;
    NSString *audioPath = [NSHomeDirectory() stringByAppendingPathComponent:@"tmp/trim.m4a"];
    NSURL *audioURL = [NSURL fileURLWithPath:audioPath];
    
    AVAsset *audioAsset = [[AVURLAsset alloc] initWithURL:audioURL options:nil];
    AVAssetTrack *audioAssetTrack = [[audioAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    AVMutableCompositionTrack *audioTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    
    [audioTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, duration) ofTrack:audioAssetTrack atTime:kCMTimeInvalid error:nil];

    // Merge;
    NSString *filename = [NSString stringWithFormat:@"tmp/movie%ld.mp4", time(nil)];
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:filename];
    unlink([path UTF8String]);
    NSURL *url = [NSURL fileURLWithPath:path];
    
//    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality];
//    exportSession.outputFileType = AVFileTypeQuickTimeMovie;
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetMediumQuality];
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.outputFileType = AVFileTypeMPEG4;
    exportSession.outputURL = url;
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        switch (exportSession.status) {
            case AVAssetExportSessionStatusFailed:
            case AVAssetExportSessionStatusCancelled:
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self mergeFailed];
				});
                break;
            }
                
            default:
            {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self mergeSuccessed:url];
				});
                break;
            }
        }
    }];
}

- (void)mergeSuccessed:(NSURL *)url
{
    [MBProgressHUD hideHUDForView:[AppDelegate sharedDelegate].window animated:YES];
    
    VideoPickerController *viewController = (VideoPickerController *)self.navigationController;
    
    if ([viewController.pickerDelegate respondsToSelector:@selector(videoPickerController:didSelectVideo:)]) {
        [viewController.pickerDelegate videoPickerController:viewController didSelectVideo:url];
    }
}

- (void)mergeFailed
{
    [MBProgressHUD hideHUDForView:[AppDelegate sharedDelegate].window animated:YES];
    [MBProgressHUD hideHUDForView:[AppDelegate sharedDelegate].window animated:YES];
    //[SVProgressHUD dismiss];
    
    VideoPickerController *viewController = (VideoPickerController *)self.navigationController;
    
    if ([viewController.pickerDelegate respondsToSelector:@selector(videoPickerController:didSelectVideo:)]) {
        [viewController.pickerDelegate videoPickerController:viewController didSelectVideo:nil];
    }
}

- (IBAction)onBtnDelete:(id)sender
{
    // Stop;
    [self stop];
    
    // Back;
    [self.navigationController popViewControllerAnimated:YES];
}

- (IBAction)onBtnApply:(id)sender
{
    MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:[AppDelegate sharedDelegate].window animated:YES];
    [hud setLabelText:@"Exporting..."];
    
    exporting = YES;
    
    // Stop;
    [self stop];
    
    // Trim;
    [self trim:YES];
}

- (IBAction)onBtnPlay:(id)sender
{
    if (!playing) {
        btnForPlay.selected = YES;
        
        exporting = NO;

        // Trim;
        [self trim:NO];
    } else {
        [self stop];
    }
}
- (void)pauseVideoWhenSleepMode{
    if (playing) {
        [self stop];
    }
}
@end
