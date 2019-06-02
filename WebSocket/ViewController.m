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

#pragma mark - CellModel

@interface CellModel : NSObject
@property (strong, nonatomic) NSString *text;
@property (strong, nonatomic) NSString *filePath;
@property (copy, nonatomic) void (^block)(void);
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

- (instancetype)initWithText:(NSString *)text client:(BOOL)client
{
    self = [self init];
    if (self) {
        _text = text;
        _client = client;
        _size = CGSizeMake(CGRectGetWidth(UIScreen.mainScreen.bounds) - 32.f, 64.f);
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

- (void)textSize:(void (^)(void))block{
    _block = block;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        self.size = [self.text boundingRectWithSize:CGSizeMake(CGRectGetWidth(UIScreen.mainScreen.bounds) - 32.f, MAXFLOAT) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:[UIFont systemFontOfSize:18.f]} context:nil].size;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            !self.block ? : self.block();
        });
    });
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

#pragma mark - ViewController

@interface ViewController ()<WebSocketDelegate, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@property (strong, nonatomic) WebSocketManager *manager;
@property (strong, nonatomic) NSMutableArray *dataSource;
@property (strong, nonatomic) NSString *urlString;

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
}

#pragma mark - Notification

- (void)keyboardWillShow:(NSNotification *)notification{
    CGRect keyboardRect = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect viewRect = [_inputView convertRect:_inputView.bounds toView:UIApplication.sharedApplication.keyWindow];
    
    [self keyboardAnimation:CGRectGetMinY(keyboardRect) - CGRectGetMaxY(viewRect)];
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
    } completion:^(BOOL finished) {
        if (self.dataSource.count) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:self.dataSource.count - 1 inSection:0];
            [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionBottom animated:YES];
        }
    }];
}

#pragma mark - UITextFieldDelegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField{
    [self didSendText:textField.text];
    textField.text = @"";
    
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

- (void)didCloseWebSocket{
    _operateItem.title = @"连接";
    
    CellModel *model = [[CellModel alloc] initWithText:@"Status Code Connection Close : 客户端" client:YES];
    [self updateModel:model];
}

- (void)didConnectWebSocket{
    _operateItem.title = @"断开";
    
    CellModel *model = [[CellModel alloc] initWithText:@"Connected WebSocket : 客户端" client:YES];
    [self updateModel:model];
}

- (void)updateModel:(CellModel *)model{
    WeakSelf;
    __weak typeof(model) weakModel = model;
    [model textSize:^{
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:[weakSelf.dataSource indexOfObject:weakModel] inSection:0];
        [weakSelf.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    }];
    [_dataSource addObject:model];
    [_tableView reloadData];
}

- (void)didSendText:(NSString *)text{
    CellModel *model = [[CellModel alloc] initWithText:[NSString stringWithFormat:@"%@ : 客户端",text] client:YES];
    [self updateModel:model];
    [_manager sendText:text];
}

- (void)didReceiveText:(NSString *)text{
    CellModel *model = [[CellModel alloc] initWithText:[NSString stringWithFormat:@"服务端 : %@",text] client:NO];
    [self updateModel:model];
}

- (void)didReceiveFile:(NSString *)filePath{
    CellModel *model = [[CellModel alloc] initWithPath:filePath];
    [_dataSource addObject:model];
}

#pragma mark - Action

- (IBAction)stopAction:(UIBarButtonItem *)sender {
    _operateItem.title = _manager.isConnected ? @"断开中..." : @"连接中...";
    _manager.isConnected ? [_manager disConnect:@"Close WebSocket"] : [_manager connect:_urlString];
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
    
    _dataSrouce = @[@"ws://121.40.165.18:8800", @"ws://123.207.167.163:9010/ajaxchattest", @"wss://echo.websocket.org", @"wss://push.niugu99.com:9100/quotation?commodityId=*"];
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
