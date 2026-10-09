#import "AmbientSettingsViewController.h"
#import "PackageManager.h"
#import "AmbientWeatherThemeController.h"
#import "AmbientLocationStore.h"
#import "AmbientLocationPickerViewController.h"
#import "AmbientPackageImporter.h"

typedef NS_ENUM(NSInteger, AmbientSettingsSection) {
    AmbientSettingsSectionWeather = 0,
    AmbientSettingsSectionTheme,
    AmbientSettingsSectionMusic,
    AmbientSettingsSectionPackages,
    AmbientSettingsSectionCount
};

static UIColor *PrimaryTextColor(void) {
    if (@available(iOS 13.0, *)) {
        return [UIColor labelColor];
    }
    return [UIColor blackColor];
}

@interface AmbientSettingsViewController () <UIDocumentPickerDelegate>
@property (nonatomic, strong) PackageManager *packageManager;
@property (nonatomic, strong) AmbientWeatherThemeController *weatherController;
@property (nonatomic, strong) AmbientLocationStore *locationStore;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation AmbientSettingsViewController

+ (NSArray<NSString *> *)observedKeys {
    return @[@"activeThemeId", @"activePlaylistId", @"installedThemes", @"installedPlaylists"];
}

- (instancetype)initWithPackageManager:(PackageManager *)packageManager
                     weatherController:(AmbientWeatherThemeController *)weatherController
                         locationStore:(AmbientLocationStore *)locationStore {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _packageManager = packageManager;
        _weatherController = weatherController;
        _locationStore = locationStore;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(done)];

    self.spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];

    // Keep the checkmarks honest if the weather controller switches themes
    // (or an import lands) while this screen is open.
    for (NSString *key in [AmbientSettingsViewController observedKeys]) {
        [self.packageManager addObserver:self forKeyPath:key options:0 context:NULL];
    }
}

- (void)dealloc {
    for (NSString *key in [AmbientSettingsViewController observedKeys]) {
        [self.packageManager removeObserver:self forKeyPath:key];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if (object == self.packageManager) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)done {
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return AmbientSettingsSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case AmbientSettingsSectionWeather:  return 2;
        case AmbientSettingsSectionTheme:    return MAX((NSInteger)self.packageManager.installedThemes.count, 1);
        case AmbientSettingsSectionMusic:    return MAX((NSInteger)self.packageManager.installedPlaylists.count, 1);
        case AmbientSettingsSectionPackages: return 1;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case AmbientSettingsSectionWeather:  return @"Weather";
        case AmbientSettingsSectionTheme:    return @"Theme";
        case AmbientSettingsSectionMusic:    return @"Music";
        case AmbientSettingsSectionPackages: return @"Packages";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case AmbientSettingsSectionWeather:
            return @"Switches to a theme tagged for the current weather at your location. Checked about every 45 minutes.";
        case AmbientSettingsSectionTheme:
            return self.packageManager.weatherAutoTheme
                ? @"Weather matching is on, so the theme changes automatically. Turn it off to choose one yourself."
                : nil;
        case AmbientSettingsSectionPackages:
            return @"Import a .zip containing a theme or music package. Importing a package with the same ID replaces the installed copy.";
    }
    return nil;
}

- (UITableViewCell *)cellWithStyle:(UITableViewCellStyle)style identifier:(NSString *)identifier {
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:identifier]
        ?: [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:identifier];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    cell.textLabel.textColor = PrimaryTextColor();
    cell.detailTextLabel.text = nil;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PackageManager *pm = self.packageManager;

    switch (indexPath.section) {
        case AmbientSettingsSectionWeather: {
            if (indexPath.row == 0) {
                UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault identifier:@"weatherSwitch"];
                cell.textLabel.text = @"Match theme to weather";
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                UISwitch *toggle = [[UISwitch alloc] init];
                toggle.on = pm.weatherAutoTheme;
                [toggle addTarget:self action:@selector(weatherSwitchChanged:) forControlEvents:UIControlEventValueChanged];
                cell.accessoryView = toggle;
                return cell;
            }
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleValue1 identifier:@"location"];
            cell.textLabel.text = @"Location";
            cell.detailTextLabel.text = [self.locationStore currentLocation].name ?: @"Not set";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        case AmbientSettingsSectionTheme: {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault identifier:@"theme"];
            if (pm.installedThemes.count == 0) {
                cell.textLabel.text = @"No themes installed";
                cell.textLabel.textColor = [UIColor grayColor];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
            AmbientTheme *theme = pm.installedThemes[(NSUInteger)indexPath.row];
            cell.textLabel.text = theme.displayName;
            BOOL locked = pm.weatherAutoTheme;
            if (locked) {
                cell.textLabel.textColor = [UIColor grayColor];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
            }
            if ([theme.themeId isEqualToString:pm.activeThemeId]) {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            return cell;
        }

        case AmbientSettingsSectionMusic: {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault identifier:@"playlist"];
            if (pm.installedPlaylists.count == 0) {
                cell.textLabel.text = @"No music packages installed";
                cell.textLabel.textColor = [UIColor grayColor];
                cell.selectionStyle = UITableViewCellSelectionStyleNone;
                return cell;
            }
            AmbientPlaylist *playlist = pm.installedPlaylists[(NSUInteger)indexPath.row];
            cell.textLabel.text = playlist.packageId;
            if ([playlist.playlistId isEqualToString:pm.activePlaylistId]) {
                cell.accessoryType = UITableViewCellAccessoryCheckmark;
            }
            return cell;
        }

        case AmbientSettingsSectionPackages: {
            UITableViewCell *cell = [self cellWithStyle:UITableViewCellStyleDefault identifier:@"import"];
            cell.textLabel.text = @"Import Package (.zip)…";
            cell.textLabel.textColor = self.view.tintColor;
            return cell;
        }
    }
    return [[UITableViewCell alloc] init];
}

#pragma mark - Actions

- (void)weatherSwitchChanged:(UISwitch *)toggle {
    // Turning it on lets the controller (which observes this property) pick a
    // theme right away; turning it off leaves the current theme in place.
    self.packageManager.weatherAutoTheme = toggle.isOn;
    [self.tableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PackageManager *pm = self.packageManager;

    switch (indexPath.section) {
        case AmbientSettingsSectionWeather:
            if (indexPath.row == 1) {
                [self showLocationPicker];
            }
            break;

        case AmbientSettingsSectionTheme: {
            if (pm.weatherAutoTheme || pm.installedThemes.count == 0) { return; }
            AmbientTheme *theme = pm.installedThemes[(NSUInteger)indexPath.row];
            NSError *error = nil;
            if (![pm setActiveThemeId:theme.themeId error:&error]) {
                [self showAlertWithTitle:@"Couldn't switch theme" message:error.localizedDescription];
            }
            break;
        }

        case AmbientSettingsSectionMusic: {
            if (pm.installedPlaylists.count == 0) { return; }
            AmbientPlaylist *playlist = pm.installedPlaylists[(NSUInteger)indexPath.row];
            NSError *error = nil;
            if (![pm setActivePlaylistId:playlist.playlistId error:&error]) {
                [self showAlertWithTitle:@"Couldn't switch music" message:error.localizedDescription];
            }
            break;
        }

        case AmbientSettingsSectionPackages:
            [self showImportPicker];
            break;
    }
}

- (void)showLocationPicker {
    __weak typeof(self) weakSelf = self;
    AmbientLocationPickerViewController *picker =
        [[AmbientLocationPickerViewController alloc] initWithLocationStore:self.locationStore
                                                                  onSelect:^(AmbientWeatherLocation *location) {
            // The controller re-reads weather-settings.json on each poll; poll now.
            [weakSelf.weatherController refreshNow];
            [weakSelf.tableView reloadData];
        }];
    [self.navigationController pushViewController:picker animated:YES];
}

#pragma mark - Import

- (void)showImportPicker {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.zip-archive", @"com.pkware.zip-archive"]
                                                               inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (urls.firstObject) {
        [self importZipAtURL:urls.firstObject];
    }
}

// Pre-iOS 11 callback.
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    [self importZipAtURL:url];
}

- (void)setBusy:(BOOL)busy {
    self.view.userInteractionEnabled = !busy;
    self.navigationItem.rightBarButtonItem.enabled = !busy;
    if (busy) {
        [self.spinner startAnimating];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.spinner];
    } else {
        [self.spinner stopAnimating];
        self.navigationItem.leftBarButtonItem = nil;
    }
}

- (void)importZipAtURL:(NSURL *)url {
    if (![url.pathExtension.lowercaseString isEqualToString:@"zip"]) {
        [self showAlertWithTitle:@"Import failed" message:@"Only .zip files can be imported."];
        return;
    }

    [self setBusy:YES];
    __weak typeof(self) weakSelf = self;
    [AmbientPackageImporter importZipAtURL:url
                            packageManager:self.packageManager
                                completion:^(NSString *summary, BOOL replaced, NSError *error) {
        // The picker handed us a temporary copy; we're done with it either way.
        [[NSFileManager defaultManager] removeItemAtURL:url error:nil];

        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        [strongSelf setBusy:NO];

        if (error) {
            [strongSelf showAlertWithTitle:@"Import failed" message:error.localizedDescription];
            return;
        }
        // A new theme may match the current weather better than the active one.
        [strongSelf.weatherController refreshNow];
        [strongSelf showAlertWithTitle:replaced ? @"Package updated" : @"Package installed"
                               message:summary];
    }];
}

#pragma mark - Helpers

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
