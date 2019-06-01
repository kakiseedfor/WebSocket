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
#import "NSObject+KVOObject.h"

#define WeakSelf __weak typeof(self) weakSelf = self;

@interface CellModel : NSObject
@property (strong, nonatomic) NSString *text;
@property (strong, nonatomic) NSString *filePath;
@property (nonatomic) CGSize size;
@property (nonatomic) BOOL client;

@end

@implementation CellModel

- (instancetype)init
{
    self = [super init];
    if (self) {
        _size = CGSizeZero;
    }
    return self;
}

- (instancetype)initWithText:(NSString *)text
{
    self = [self init];
    if (self) {
        _text = text;
        [self textSize];
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

- (void)textSize{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.size = [self.text boundingRectWithSize:CGSizeMake(CGRectGetWidth(UIScreen.mainScreen.bounds) - 32.f, MAXFLOAT) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:18.f]} context:nil].size;
    });
}

@end

@interface TableViewCell : UITableViewCell
@property (strong, nonatomic) UILabel *text;
@property (strong, nonatomic) UIView *seperator;
@property (strong, nonatomic) UIImageView *image;

@end

@implementation TableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    
    if (self) {
        [self.contentView addSubview:self.text];
        [self.contentView addSubview:self.seperator];
        [_text mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.top.equalTo(self.contentView).offset(16.f);
            make.bottom.right.equalTo(self.contentView).offset(-16.f);
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
    _text.textAlignment = model.client ? NSTextAlignmentRight : NSTextAlignmentLeft;
}

- (UILabel *)text{
    if (!_text) {
        UILabel *temp = [[UILabel alloc] init];
        temp.font = [UIFont systemFontOfSize:16.f];
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

@end

@interface ViewController ()<WebSocketDelegate, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (strong, nonatomic) WebSocketManager *manager;
@property (strong, nonatomic) NSMutableArray *dataSource;
@property (strong, nonatomic) UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIView *inputView;
@property (weak, nonatomic) IBOutlet UIButton *optionBtn;
@property (weak, nonatomic) IBOutlet UITextField *textField;

@end

@implementation ViewController

- (void)dealloc{
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
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
        make.bottom.left.right.equalTo(self.view);
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
}

#pragma mark - Notification

- (void)keyboardWillShow:(NSNotification *)notification{
    CGRect keyboardRect = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect viewRect = [self.inputView convertRect:self.inputView.bounds toView:UIApplication.sharedApplication.keyWindow];
    
    [self keyboardAnimation:CGRectGetMinY(keyboardRect) - CGRectGetMaxY(viewRect)];
}

- (void)keyboardWillHide:(NSNotification *)notification{
    [self keyboardAnimation:0.f];
}

- (void)keyboardAnimation:(CGFloat)offset{
    [_inputView mas_updateConstraints:^(MASConstraintMaker *make) {
        make.bottom.equalTo(self.view.mas_bottom).offset(offset);
    }];
    
    [UIView animateWithDuration:.25f animations:^{
        [self.view layoutIfNeeded];
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    [self didSendText:textField.text];
    
    [textField resignFirstResponder];
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

- (void)didConnectWebSocket{
    NSLog(@"%s",__FUNCTION__);
}

- (void)updateModel:(CellModel *)model{
    [_dataSource addObject:model];
    [_tableView reloadData];
    
    WeakSelf;
    __weak typeof(model) weakModel = model;
    [model.kvoController addObserver:self forKeyPath:@"size" options:NSKeyValueObservingOptionNew kvoCallBack:^(id context) {
        [weakModel.kvoController removeObserver:self forKeyPath:@"size"];
        dispatch_async(dispatch_get_main_queue(), ^{
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[self.dataSource indexOfObject:weakModel] inSection:0];
            [weakSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        });
    }];
}

- (void)didSendText:(NSString *)text{
    CellModel *model = [[CellModel alloc] initWithText:[NSString stringWithFormat:@"%@ : 客户端",text]];
    model.client = YES;
    
    [self updateModel:model];
    [_manager sendText:text];
}

- (void)didReceiveText:(NSString *)text{
    CellModel *model = [[CellModel alloc] initWithText:[NSString stringWithFormat:@"服务端 : %@",text]];
    [self updateModel:model];
}

- (void)didReceiveFile:(NSString *)filePath{
    CellModel *model = [[CellModel alloc] initWithPath:filePath];
    [_dataSource addObject:model];
}

#pragma mark - Action

- (IBAction)stopAction:(UIBarButtonItem *)sender {
//    "wss://push.niugu99.com:9100/quotation?commodityId=*"
    _manager.isConnected ? [_manager disConnect:@"Hello"] : [_manager connect:@"wss://echo.websocket.org"];
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
