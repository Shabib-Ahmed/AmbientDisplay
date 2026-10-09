#import "AmbientLocationPickerViewController.h"
#import "AmbientLocationStore.h"

@interface AmbientLocationPickerViewController () <UISearchBarDelegate>
@property (nonatomic, strong) AmbientLocationStore *store;
@property (nonatomic, copy) void (^onSelect)(AmbientWeatherLocation *);
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) NSURLSessionDataTask *searchTask;
@property (nonatomic, copy) NSArray<AmbientWeatherLocation *> *results;
@property (nonatomic, copy, nullable) NSString *statusText;
@end

@implementation AmbientLocationPickerViewController

- (instancetype)initWithLocationStore:(AmbientLocationStore *)store
                             onSelect:(void (^)(AmbientWeatherLocation *))onSelect {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        _store = store;
        _onSelect = [onSelect copy];
        _results = @[];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Location";

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.placeholder = @"Search for a city";
    self.searchBar.delegate = self;
    self.searchBar.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.searchBar.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tableView.tableHeaderView = self.searchBar;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self.searchBar becomeFirstResponder];
}

- (void)dealloc {
    [self.searchTask cancel];
}

#pragma mark Search

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSString *query = [searchBar.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [searchBar resignFirstResponder];

    if (query.length < 2) {
        self.results = @[];
        self.statusText = @"Type at least two letters.";
        [self.tableView reloadData];
        return;
    }

    [self.searchTask cancel];
    self.results = @[];
    self.statusText = @"Searching…";
    [self.tableView reloadData];

    __weak typeof(self) weakSelf = self;
    self.searchTask = [self.store searchPlacesNamed:query completion:^(NSArray<AmbientWeatherLocation *> *results, NSError *error) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        if (error) {
            strongSelf.results = @[];
            strongSelf.statusText = [NSString stringWithFormat:@"Search failed: %@", error.localizedDescription];
        } else {
            strongSelf.results = results;
            strongSelf.statusText = results.count ? nil : @"No matching places.";
        }
        [strongSelf.tableView reloadData];
    }];
}

#pragma mark Table

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    AmbientWeatherLocation *current = [self.store currentLocation];
    return current ? [NSString stringWithFormat:@"Current: %@", current.name] : @"No location set";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.results.count) { return (NSInteger)self.results.count; }
    return self.statusText ? 1 : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *ident = @"place";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:ident]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:ident];

    if (self.results.count) {
        cell.textLabel.text = self.results[(NSUInteger)indexPath.row].name;
        cell.textLabel.textColor = [UIColor blackColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        cell.textLabel.text = self.statusText;
        cell.textLabel.textColor = [UIColor grayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    cell.textLabel.numberOfLines = 0;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (!self.results.count) { return; }

    AmbientWeatherLocation *picked = self.results[(NSUInteger)indexPath.row];
    NSError *error = nil;
    if (![self.store saveLocation:picked error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Couldn't save location"
                                                                       message:error.localizedDescription
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    if (self.onSelect) { self.onSelect(picked); }
    [self.navigationController popViewControllerAnimated:YES];
}

@end
