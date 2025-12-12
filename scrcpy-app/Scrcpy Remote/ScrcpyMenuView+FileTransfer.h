//
//  ScrcpyMenuView+FileTransfer.h
//  Scrcpy Remote
//
//  File transfer category for ScrcpyMenuView
//

#import "ScrcpyMenuView.h"
#import <PhotosUI/PhotosUI.h>

NS_ASSUME_NONNULL_BEGIN

API_AVAILABLE(ios(14.0))
@interface ScrcpyMenuView (FileTransfer) <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>

// ActionSheet for choosing source
- (void)showSendFilesOrPhotosActionSheet;

// File Picker
- (void)showFilePicker;
- (void)showPhotoPicker API_AVAILABLE(ios(14.0));
- (UIViewController *)topViewController;

// File Transfer Progress UI
- (void)showFileTransferProgress;
- (void)hideFileTransferProgress;
- (void)updateFileProgress:(NSInteger)fileIndex progress:(float)progress status:(NSString *)status;
- (void)cancelFileTransfer;

// ADB File Transfer
- (void)startFileTransfer;
- (void)transferFile:(NSURL *)fileURL atIndex:(NSInteger)index;
- (void)transferNextFile;
- (void)simulateProgressForFile:(NSInteger)index;
- (void)updateFileTransferCompletionUI;

@end

NS_ASSUME_NONNULL_END
