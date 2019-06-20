//
//  ViewController.m
//  WebSocket
//
//  Created by kakiYen on 2019/5/20.
//  Copyright © 2019 kakiYen. All rights reserved.
//

#import "Masonry.h"
#import "ViewController.h"
#import "WebSocketManager.h"

#import <Photos/Photos.h>
#import <AVFoundation/AVFoundation.h>

#define WeakSelf __weak typeof(self) weakSelf = self;

#pragma mark - CellModel

@interface CellModel : NSObject
@property (strong, nonatomic) NSString *text;
@property (strong, nonatomic) NSString *filePath;
@property (strong, nonatomic) UIImage *image;
@property (copy, nonatomic) void (^block)(void);
@property (nonatomic) CGSize size;
@property (nonatomic) BOOL client;

@end

@implementation CellModel

- (instancetype)initWithText:(NSString *)text client:(BOOL)client
{
    self = [self init];
    if (self) {
        _size = CGSizeZero;
        _text = text;
        _client = client;
    }
    return self;
}

- (instancetype)initWithPath:(NSString *)filePath
{
    self = [super init];
    if (self) {
        _filePath = filePath;
        _size = CGSizeMake(120.f, 150.f);
    }
    return self;
}

- (void)bitMap{
    UIImage *image = [UIImage imageWithContentsOfFile:self.filePath];
    
    CGFloat widthRatio = self.size.width / image.size.width;
    CGFloat heightRatio = self.size.height / image.size.height;
    CGFloat width = (widthRatio < heightRatio ? self.size.width : image.size.height * heightRatio);
    CGFloat height = (widthRatio < heightRatio ? image.size.height * widthRatio : self.size.height);
    CGContextRef contextRef = CGBitmapContextCreate(NULL, width, height, CGImageGetBitsPerComponent(image.CGImage), 0, CGColorSpaceCreateDeviceRGB(), kCGImageAlphaNoneSkipLast);
    CGContextDrawImage(contextRef, CGRectMake(0.f, 0.f, width, height), image.CGImage);
    CGImageRef imageRef = CGBitmapContextCreateImage(contextRef);
    
    self.image = [UIImage imageWithCGImage:imageRef scale:image.scale orientation:image.imageOrientation];
    
    CFRelease(contextRef);
    CFRelease(imageRef);
}

- (void)textSize{
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineSpacing = 0.1f;
    paragraphStyle.alignment = NSTextAlignmentJustified;
    
    self.size = [self.text boundingRectWithSize:CGSizeMake(CGRectGetWidth(UIScreen.mainScreen.bounds) - 32.f, MAXFLOAT) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName : [UIFont systemFontOfSize:18.f], NSParagraphStyleAttributeName : paragraphStyle} context:nil].size;
}

@end

#pragma mark - TableViewCell

@interface TableViewCell : UITableViewCell
@property (strong, nonatomic) UILabel *text;
@property (strong, nonatomic) UIView *seperator;
@property (strong, nonatomic) UIImageView *image;

@end

@implementation TableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    
    if (self) {
        [self.contentView addSubview:self.image];
        [self.contentView addSubview:self.text];
        [self.contentView addSubview:self.seperator];
        [_text mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.top.equalTo(self.contentView).offset(16.f);
            make.bottom.right.equalTo(self.contentView).offset(-16.f);
        }];
        
        [_image mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(self.contentView);
            make.width.mas_equalTo(120.f);
            make.height.mas_equalTo(150.f);
        }];
        
        [_seperator mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.bottom.right.equalTo(self.contentView);
            make.height.mas_equalTo(1.f);
        }];
    }
    
    return self;
}

- (void)updateView:(CellModel *)model{
    _text.text = model.text;
    _text.hidden = model.filePath.length ? YES : NO;
    _text.textAlignment = model.client ? NSTextAlignmentRight : NSTextAlignmentLeft;
    
    _image.hidden = model.filePath.length ? NO : YES;
    _image.image = model.image;
}

- (UILabel *)text{
    if (!_text) {
        UILabel *temp = [[UILabel alloc] init];
        temp.font = [UIFont systemFontOfSize:18.f];
        temp.numberOfLines = 0;
        _text = temp;
    }
    
    return _text;
}

- (UIView *)seperator{
    if (!_seperator) {
        UIView *temp = [[UIView alloc] init];
        temp.backgroundColor = UIColor.grayColor;
        _seperator =  temp;
    }
    
    return _seperator;
}

- (UIImageView *)image{
    if (!_image) {
        UIImageView *temp = [[UIImageView alloc] init];
        temp.contentMode = UIViewContentModeScaleAspectFit;
        _image = temp;
    }
    
    return _image;
}

@end

#pragma mark - ViewController

@interface ViewController ()<WebSocketDelegate, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property (strong, nonatomic) WebSocketManager *manager;
@property (strong, nonatomic) NSMutableArray *dataSource;
@property (strong, nonatomic) NSString *urlString;

@property (nonatomic) dispatch_semaphore_t semaphore;
@property (strong, nonatomic) UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIView *inputView;
@property (weak, nonatomic) IBOutlet UIButton *optionBtn;
@property (weak, nonatomic) IBOutlet UITextField *textField;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *operateItem;

@end

@implementation ViewController

- (void)dealloc{
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    self.navigationItem.title = @"Chat Room";
    
    _semaphore = dispatch_semaphore_create(1);
    _dataSource = [NSMutableArray array];
    _manager = [[WebSocketManager alloc] initWith:self];
    
    [self.view addSubview:self.tableView];
    [self.view addSubview:self.inputView];
    [self.view addSubview:self.optionBtn];
    [self.view addSubview:self.textField];
    [_tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.left.right.equalTo(self.view);
        make.bottom.equalTo(self.inputView.mas_top);
    }];
    
    [_inputView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(self.mas_bottomLayoutGuideTop);
        make.left.right.equalTo(self.view);
        make.height.mas_equalTo(48.f);
    }];
    
    [_optionBtn mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.view.mas_right).offset(-16.f);
        make.centerY.equalTo(self.inputView.mas_centerY);
    }];
    
    [_textField mas_makeConstraints:^(MASConstraintMaker *make) {
        make.right.equalTo(self.optionBtn.mas_left).offset(-12.f);
        make.left.equalTo(self.view.mas_left).offset(16.f);
        make.centerY.equalTo(self.inputView.mas_centerY);
    }];
    
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapAciton:)];
    tap.numberOfTapsRequired = 1;
    [self.view addGestureRecognizer:tap];
}

- (void)showStyleSheet{
    UIAlertController *alertVC = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        
    }];
    UIAlertAction *photoAction = [UIAlertAction actionWithTitle:@"拍照" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self photoAction];
    }];
    UIAlertAction *albumAction = [UIAlertAction actionWithTitle:@"选择照片" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self albumAction];
    }];
    [alertVC addAction:photoAction];
    [alertVC addAction:albumAction];
    [alertVC addAction:cancelAction];
    
    [self presentViewController:alertVC animated:YES completion:^{}];
}

#pragma mark - Action

- (IBAction)stopAction:(UIBarButtonItem *)sender {
    _operateItem.title = _manager.isConnected ? @"断开中..." : @"连接中...";
    _manager.isConnected ? [_manager disConnect:@"Close WebSocket"] : [_manager connect:_urlString];
}

- (IBAction)optionAction:(id)sender {
    [_textField resignFirstResponder];
    [self showStyleSheet];
}

- (void)tapAciton:(UITapGestureRecognizer *)tap{
    [_textField resignFirstResponder];
}

- (void)scrollToBottom{
    
}

- (void)photoAction{
    BOOL valid = [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
    valid = [UIImagePickerController isCameraDeviceAvailable:UIImagePickerControllerCameraDeviceRear];
    
    if (valid) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
        
        if (device) {
            AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
            switch (authStatus) {
                case AVAuthorizationStatusRestricted:
                case AVAuthorizationStatusDenied:
                    NSLog(@"应用相机权限受限,请在设置中启用");
                    break;
                case AVAuthorizationStatusNotDetermined:{
                    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
                        !granted ? : dispatch_async(dispatch_get_main_queue(), ^{
                            [self showAlbum:UIImagePickerControllerSourceTypeCamera];
                        });
                    }];
                }
                    break;
                default:
                    [self showAlbum:UIImagePickerControllerSourceTypeCamera];
                    break;
            }
        }
    }
}

- (void)albumAction{
    PHAuthorizationStatus authStatus = [PHPhotoLibrary authorizationStatus];//读取设备授权状态
    
    switch (authStatus) {
        case PHAuthorizationStatusRestricted:
        case PHAuthorizationStatusDenied:
            NSLog(@"应用相机权限受限,请在设置中启用");
            break;
        case PHAuthorizationStatusNotDetermined:{
            [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
                if (status == PHAuthorizationStatusAuthorized) {
                    [self showAlbum:UIImagePickerControllerSourceTypePhotoLibrary];
                }
            }];
        }
            break;
        default:
            [self showAlbum:UIImagePickerControllerSourceTypePhotoLibrary];
            break;
    }
}

- (void)showAlbum:(UIImagePickerControllerSourceType)sourceType{
    UIImagePickerController * imagePicker = [[UIImagePickerController alloc] init];
    imagePicker.editing = YES;
    imagePicker.delegate = self;
    imagePicker.allowsEditing = YES;
    imagePicker.sourceType = sourceType;
    
    UINavigationBar.appearance.translucent = NO;
    [self presentViewController:imagePicker animated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate, UINavigationControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *,id> *)info {
//    PHAsset *asset = info[@"UIImagePickerControllerPHAsset"];
//    [PHImageManager.defaultManager requestImageForAsset:asset targetSize:PHImageManagerMaximumSize contentMode:PHImageContentModeDefault options:nil resultHandler:^(UIImage * _Nullable result, NSDictionary * _Nullable info) {
//        NSURL *url = info[@"PHImageFileURLKey"];
//        [self.manager sendFile:url.relativePath];
//    }];
    
    UIImage *image = info [@"UIImagePickerControllerEditedImage"];
    [_manager sendData:UIImageJPEGRepresentation(image, 0.f)];
    [self imagePickerControllerDidCancel:picker];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker{
    [picker dismissViewControllerAnimated:YES completion:^{
    }];
}

#pragma mark - Notification

- (void)keyboardWillShow:(NSNotification *)notification{
    CGRect keyboardRect = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect viewRect = [_inputView convertRect:_inputView.bounds toView:UIApplication.sharedApplication.keyWindow];
    
    CGFloat offset = CGRectGetMinY(keyboardRect) - CGRectGetMaxY(viewRect);
    !(offset < 0) ? : [self keyboardAnimation:offset];
}

- (void)keyboardWillHide:(NSNotification *)notification{
    [self keyboardAnimation:0.f];
}

- (void)keyboardAnimation:(CGFloat)offset{
    [_inputView mas_updateConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(self.view.mas_bottom).offset(offset - self.view.safeAreaInsets.bottom);
    }];
    
    [UIView animateWithDuration:.25f animations:^{
        [self.view layoutIfNeeded];
    }];
    
    if (ABS(offset) && self.dataSource.count) {
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:NO];
    }
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    [self didSendText:textField.text];
    textField.text = @"";
    
    return YES;
}

#pragma mark - UITableViewDelegate, UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return _dataSource.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath{
    CellModel *model = [_dataSource objectAtIndex:indexPath.row];
    return model.size.height + 32.f;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    TableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"TableViewCell" forIndexPath:indexPath];
    CellModel *model = [_dataSource objectAtIndex:indexPath.row];
    [cell updateView:model];
    
    return cell;
}

#pragma mark - WebSocketDelegate

- (void)didCloseWebSocket{
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    
    CellModel *model = [[CellModel alloc] initWithText:@"Status Code Connection Close : 客户端" client:YES];
    [model textSize];
    [self.dataSource addObject:model];
    
    [self finalizeOperation];
}

- (void)didConnectWebSocket{
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    
    CellModel *model = [[CellModel alloc] initWithText:@"Connected WebSocket : 客户端" client:YES];
    [model textSize];
    [self.dataSource addObject:model];
    
    [self finalizeOperation];
}

- (void)connectionWithError:(NSError *)error{
    UIAlertController *alertVC = [UIAlertController alertControllerWithTitle:@"提示" message:error.domain preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancleAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
    }];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"重新连接" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self stopAction:self.operateItem];
    }];
    [alertVC addAction:cancleAction];
    [alertVC addAction:confirmAction];
    
    [self presentViewController:alertVC animated:YES completion:^{
    }];
}

- (void)finalizeOperation{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.operateItem.title = self.manager.isConnected ? @"断开" : @"连接";
        
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0];
        [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionNone animated:YES];
        
        dispatch_semaphore_signal(self.semaphore);
    });
}

- (void)didSendText:(NSString *)text{
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    
    CellModel *model = [[CellModel alloc] initWithText:[NSString stringWithFormat:@"%@ : 客户端",text] client:YES];
    [model textSize];
    [self.dataSource addObject:model];
    
    [self finalizeOperation];
    [_manager sendText:text];
}

- (void)didReceiveText:(NSString *)text{
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    
    CellModel *model = [[CellModel alloc] initWithText:[NSString stringWithFormat:@"服务端 : %@",text] client:NO];
    [model textSize];
    [self.dataSource addObject:model];
    
    [self finalizeOperation];
}

- (void)didReceiveFile:(NSString *)filePath{
    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
    
    CellModel *model = [[CellModel alloc] initWithPath:filePath];
    [model bitMap];
    [self.dataSource addObject:model];
    
    [self finalizeOperation];
}

#pragma mark - Method

- (UITableView *)tableView{
    if (!_tableView) {
        UITableView *tempTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
        tempTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        tempTableView.backgroundColor = UIColor.whiteColor;
        tempTableView.dataSource = self;
        tempTableView.delegate = self;
        [tempTableView registerClass:TableViewCell.class forCellReuseIdentifier:@"TableViewCell"];
        _tableView = tempTableView;
    }
    
    return _tableView;
}

@end

#pragma mark - RootViewController

@interface RootViewController : UIViewController<UITableViewDelegate, UITableViewDataSource>
@property (strong, nonatomic) NSArray *dataSrouce;
@property (weak, nonatomic) IBOutlet UITableView *tableView;

@end

@implementation RootViewController

- (void)viewDidLoad{
    [super viewDidLoad];
    
    self.navigationItem.title = @"Socket Lists";
    
    _dataSrouce = @[@"ws://121.40.165.18:8800", @"ws://119.29.3.36:6700/", @"ws://123.207.167.163:9010/ajaxchattest", @"wss://echo.websocket.org", @"wss://push.niugu99.com:9100/quotation?commodityId=*", @"ws://10.0.2.20:8080/", @"ws://192.168.90.216:3457/mktdata?contractid=5237"];
    [_tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"UITableViewCell"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{
    return _dataSrouce.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"UITableViewCell" forIndexPath:indexPath];
    cell.textLabel.text = _dataSrouce[indexPath.row];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath{
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:NSBundle.mainBundle];
    ViewController *vc = [storyboard instantiateViewControllerWithIdentifier:@"ViewController"];
    vc.urlString = _dataSrouce[indexPath.row];
    
    [self.navigationController pushViewController:vc animated:YES];
}

@end
