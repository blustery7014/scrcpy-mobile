//
//  ScrcpyMenuView+FileTransfer.h
//  Scrcpy Remote
//
//  File transfer category for ScrcpyMenuView
//

#import "ScrcpyMenuView.h"

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyMenuView (FileTransfer) <UIDocumentPickerDelegate>

// File Picker
- (void)showFilePicker;
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
