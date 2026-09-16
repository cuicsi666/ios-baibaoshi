// main.m - ESXi Monitor Standalone v3.0.0
// 零中转：内置 libssh2 直连 ESXi
// 功能：温度/CPU/内存/存储/网络监控 + VM开关/快照管理/自启 + 温度曲线 + 磁盘预警 + 连接状态 + 操作日志
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <arpa/inet.h>
#import <netdb.h>
#import <sys/socket.h>
#import <sys/time.h>
#import <string.h>
#import <pthread.h>
#import <math.h>
#import <libssh2.h>
#import <AudioToolbox/AudioToolbox.h>

// ══════════════════════════════════════════════════════════════
// C 层：SSH 持久连接 + 执行
// ══════════════════════════════════════════════════════════════
static char gKbdPass[512];
static void KbdIntCallback(const char *name, int name_len,
                           const char *instruction, int instruction_len,
                           int num_prompts,
                           const LIBSSH2_USERAUTH_KBDINT_PROMPT *prompts,
                           LIBSSH2_USERAUTH_KBDINT_RESPONSE *responses,
                           void **abstract) {
    if (num_prompts <= 0) return;
    for (int i = 0; i < num_prompts; i++) {
        responses[i].text = strdup(gKbdPass);
        responses[i].length = (unsigned int)strlen(gKbdPass);
    }
}

static pthread_mutex_t gSSHLock = PTHREAD_MUTEX_INITIALIZER;
static int gSock = -1;
static LIBSSH2_SESSION *gSession = NULL;
static NSString *gConnHost = nil, *gConnUser = nil, *gConnPass = nil;
static int gConnPort = 22;

static void SSHClose(void) {
    if (gSession) {
        libssh2_session_disconnect(gSession, "bye");
        libssh2_session_free(gSession);
        gSession = NULL;
    }
    if (gSock >= 0) { close(gSock); gSock = -1; }
}

static BOOL SSHEnsureConnected(NSString *host, int port, NSString *user, NSString *pass, NSString **errOut) {
    *errOut = nil;
    if (gSock >= 0 && gSession &&
        [gConnHost isEqualToString:host] && gConnPort == port &&
        [gConnUser isEqualToString:user] && [gConnPass isEqualToString:pass]) {
        return YES;
    }
    SSHClose();
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) { *errOut = @"socket 创建失败"; return NO; }
    struct sockaddr_in sin; memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host.UTF8String, &sin.sin_addr) != 1) {
        struct hostent *he = gethostbyname(host.UTF8String);
        if (!he) { close(sock); *errOut = @"主机解析失败"; return NO; }
        memcpy(&sin.sin_addr, he->h_addr, he->h_length);
    }
    struct timeval tv = {20, 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    if (connect(sock, (struct sockaddr *)&sin, sizeof(sin)) != 0) {
        close(sock); *errOut = @"连接 ESXi 失败（网络不通）"; return NO;
    }
    LIBSSH2_SESSION *session = libssh2_session_init();
    if (!session) { close(sock); *errOut = @"SSH 初始化失败"; return NO; }
    libssh2_session_set_timeout(session, 25000);
    if (libssh2_session_handshake(session, sock) != 0) {
        *errOut = @"SSH 握手失败（可能是端口/版本问题）";
        libssh2_session_free(session); close(sock); return NO;
    }
    int auth_rc = -1;
    snprintf(gKbdPass, sizeof(gKbdPass), "%s", pass.UTF8String ?: "");
    auth_rc = libssh2_userauth_keyboard_interactive_ex(session, user.UTF8String,
                                                       (unsigned int)strlen(user.UTF8String),
                                                       &KbdIntCallback);
    if (auth_rc != 0) {
        auth_rc = libssh2_userauth_password(session, user.UTF8String, pass.UTF8String);
    }
    if (auth_rc != 0) {
        *errOut = @"SSH 认证失败（用户名/密码错误）";
        libssh2_session_disconnect(session, "auth failed");
        libssh2_session_free(session); close(sock); return NO;
    }
    gSock = sock; gSession = session;
    gConnHost = host; gConnPort = port; gConnUser = user; gConnPass = pass;
    return YES;
}

static NSString *SSHExecRaw(NSString *host, int port, NSString *user, NSString *pass,
                            NSString *cmd, BOOL allowEmpty, NSString **errOut) {
    *errOut = nil;
    pthread_mutex_lock(&gSSHLock);
    NSString *result = nil;
    if (!SSHEnsureConnected(host, port, user, pass, errOut)) {
        pthread_mutex_unlock(&gSSHLock);
        return nil;
    }
    LIBSSH2_CHANNEL *channel = libssh2_channel_open_session(gSession);
    if (!channel) {
        *errOut = @"SSH 通道打开失败"; SSHClose();
        pthread_mutex_unlock(&gSSHLock); return nil;
    }
    if (libssh2_channel_exec(channel, cmd.UTF8String) != 0) {
        *errOut = @"命令执行失败";
        libssh2_channel_free(channel); SSHClose();
        pthread_mutex_unlock(&gSSHLock); return nil;
    }
    NSMutableData *outData = [NSMutableData data];
    char buf[16384]; ssize_t n;
    while ((n = libssh2_channel_read(channel, buf, sizeof(buf))) > 0) {
        [outData appendBytes:buf length:(NSUInteger)n];
    }
    if (n < 0) {
        libssh2_channel_free(channel); SSHClose();
        *errOut = @"SSH 读取失败（连接中断）";
        pthread_mutex_unlock(&gSSHLock); return nil;
    }
    while (libssh2_channel_read_stderr(channel, buf, sizeof(buf)) > 0) {}
    libssh2_channel_send_eof(channel);
    libssh2_channel_wait_eof(channel);
    libssh2_channel_close(channel);
    libssh2_channel_free(channel);
    if (outData.length == 0 && !allowEmpty) {
        *errOut = @"无返回数据";
        pthread_mutex_unlock(&gSSHLock); return nil;
    }
    result = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
    pthread_mutex_unlock(&gSSHLock);
    return result;
}

static NSString *SSHExec(NSString *host, int port, NSString *user, NSString *pass,
                         NSString *cmd, NSString **errOut) {
    return SSHExecRaw(host, port, user, pass, cmd, NO, errOut);
}

// ══════════════════════════════════════════════════════════════
// VM 数据模型
// ══════════════════════════════════════════════════════════════
@interface VMInfo : NSObject
@property (nonatomic, copy) NSString *vmid;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *state;       // running/off/suspended/unknown
@property (nonatomic) int cpuMhz;                  // 实时 CPU 占用 MHz
@property (nonatomic) int guestMemMB;
@property (nonatomic) int hostMemMB;
@property (nonatomic) BOOL autostart;              // 开机自启
@property (nonatomic, strong) NSMutableArray *snapshots; // NSDictionary: name/id/date
@end
@implementation VMInfo
- (instancetype)init {
    self = [super init];
    if (self) { _snapshots = [NSMutableArray array]; }
    return self;
}
@end

// ══════════════════════════════════════════════════════════════
// 远端采集脚本 + 解析
// ══════════════════════════════════════════════════════════════
static NSString *BuildCommand(NSString *deviceId, BOOL full) {
    // 快速刷新：只查核心数据 + VM 状态/资源（每台 VM 1 次 vim-cmd）
    // 完整刷新：额外查自启 + 快照（低频，30 秒一次）
    NSString *extra = @"";
    if (full) {
        extra = [NSString stringWithFormat:
            @"echo \"BEGIN:AS\"\n"
            @"vim-cmd hostsvc/autostartmanager/get_autostartseq 2>/dev/null | grep -E \"key =|startAction\"\n"
            @"echo \"END:AS\"\n"
            @"vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1{print $1\"|\"$2}' | while IFS='|' read -r vid vname; do\n"
            @"  echo \"BEGIN:SNAP:$vid\"\n"
            @"  vim-cmd vmsvc/snapshot.get \"$vid\" 2>/dev/null | grep -E \"Snapshot Name|Snapshot Id|Snapshot Created\"\n"
            @"  echo \"END:SNAP:$vid\"\n"
            @"done\n"];
    }
    return [NSString stringWithFormat:
        @"U=$(uptime 2>/dev/null); echo \"UPTIME:$U\"\n"
        @"TEMP=$(esxcli storage core device smart get -d '%@' 2>/dev/null | grep -i 'Drive Temperature'); echo \"TEMP:$TEMP\"\n"
        @"CORES=$(grep -c processor /proc/cpuinfo 2>/dev/null); echo \"CORES:$CORES\"\n"
        @"D1=$(df -h /vmfs/volumes/ssd 2>/dev/null | tail -1); echo \"DS1:$D1\"\n"
        @"D2=$(df -h /vmfs/volumes/Test_datastore 2>/dev/null | tail -1); echo \"DS2:$D2\"\n"
        @"VST=$(vsish -e get /memory/comprehensive 2>/dev/null | grep 'Physical memory estimate' | grep -oE '[0-9]+'); echo \"VST:$VST\"\n"
        @"VSF=$(vsish -e get /memory/comprehensive 2>/dev/null | grep -E '^   Free:' | grep -oE '[0-9]+'); echo \"VSF:$VSF\"\n"
        @"vim-cmd vmsvc/getallvms 2>/dev/null | awk 'NR>1{print $1\"|\"$2}' | while IFS='|' read -r vid vname; do\n"
        @"  echo \"BEGIN:SUM:$vid\"\n"
        @"  vim-cmd vmsvc/get.summary \"$vid\" 2>/dev/null | grep -E \"powerState|overallCpuUsage|guestMemoryUsage|hostMemoryUsage|uptimeSeconds\"\n"
        @"  echo \"END:SUM:$vid\"\n"
        @"done\n"
        @"%@",
        deviceId, extra];
}

// 正则取第一个匹配组
static NSString *RegexFirst(NSString *s, NSString *pattern) {
    if (!s) return nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (m && m.numberOfRanges > 1) return [s substringWithRange:[m rangeAtIndex:1]];
    return nil;
}
static NSString *RegexLineFirst(NSString *line, NSString *pattern) {
    return RegexFirst(line, pattern);
}

static NSMutableArray *ParseOutput(NSString *raw) {
    if (!raw) return nil;
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSMutableArray *vms = [NSMutableArray array];
    NSMutableDictionary *sumBlocks = [NSMutableDictionary dictionary]; // vid -> 拼接文本
    NSMutableDictionary *snapBlocks = [NSMutableDictionary dictionary]; // vid -> 拼接文本
    NSMutableArray *asLines = [NSMutableArray array];
    int cores = 1;

    NSArray *lines = [raw componentsSeparatedByString:@"\n"];
    NSString *curSumVid = nil, *curSnapVid = nil, *inAS = nil;
    for (NSString *ln in lines) {
        if ([ln hasPrefix:@"UPTIME:"]) d[@"uptime"] = [ln substringFromIndex:7];
        else if ([ln hasPrefix:@"TEMP:"]) d[@"temp_line"] = [ln substringFromIndex:5];
        else if ([ln hasPrefix:@"CORES:"]) cores = [[ln substringFromIndex:6] intValue] ?: 1;
        else if ([ln hasPrefix:@"DS1:"]) d[@"ds1"] = [ln substringFromIndex:4];
        else if ([ln hasPrefix:@"DS2:"]) d[@"ds2"] = [ln substringFromIndex:4];
        else if ([ln hasPrefix:@"VST:"]) d[@"vst"] = [ln substringFromIndex:4];
        else if ([ln hasPrefix:@"VSF:"]) d[@"vsf"] = [ln substringFromIndex:4];
        else if ([ln hasPrefix:@"BEGIN:AS"]) inAS = @"";
        else if ([ln hasPrefix:@"END:AS"]) inAS = nil;
        else if (inAS) [asLines addObject:ln];
        else if ([ln hasPrefix:@"BEGIN:SUM:"]) curSumVid = [ln substringFromIndex:10];
        else if ([ln hasPrefix:@"END:SUM:"]) curSumVid = nil;
        else if (curSumVid) { sumBlocks[curSumVid] = [NSString stringWithFormat:@"%@\n%@", sumBlocks[curSumVid] ?: @"", ln]; }
        else if ([ln hasPrefix:@"BEGIN:SNAP:"]) curSnapVid = [ln substringFromIndex:11];
        else if ([ln hasPrefix:@"END:SNAP:"]) curSnapVid = nil;
        else if (curSnapVid) { snapBlocks[curSnapVid] = [NSString stringWithFormat:@"%@\n%@", snapBlocks[curSnapVid] ?: @"", ln]; }
    }

    // 从 get.summary 块生成 VM 列表（每台 VM 1 次 vim-cmd，含名称+状态+资源）
    for (NSString *vid in sumBlocks) {
        NSString *sum = sumBlocks[vid] ?: @"";
        NSString *nm = RegexFirst(sum, @"name = \"([^\"]+)\"");
        if (!nm) continue;
        VMInfo *v = [VMInfo new];
        v.vmid = vid;
        v.name = nm;
        NSString *ps = RegexFirst(sum, @"powerState = \"(\w+)\"");
        NSString *sl = (ps ?: @"").lowercaseString;
        v.state = [sl containsString:@"poweredon"] ? @"running" :
                  ([sl containsString:@"poweredoff"] ? @"off" :
                   ([sl containsString:@"suspended"] ? @"suspended" : @"unknown"));
        [vms addObject:v];
    }

    // 自启信息
    for (NSString *ln in asLines) {
        NSString *key = RegexLineFirst(ln, @"key = 'vim\\.VirtualMachine:(\\d+)'");
        if (key) {
            NSString *act = nil;
            for (NSString *ln2 in asLines) {
                if ([ln2 containsString:[NSString stringWithFormat:@"VirtualMachine:%@'", key]]) {
                    // 找同块后续 startAction
                }
            }
            NSString *action = nil;
            BOOL foundKey = NO;
            for (NSString *ln3 in asLines) {
                NSString *k3 = RegexLineFirst(ln3, @"key = 'vim\\.VirtualMachine:(\\d+)'");
                if (k3) {
                    foundKey = [k3 isEqualToString:key];
                    continue;
                }
                if (foundKey) {
                    NSString *a = RegexLineFirst(ln3, @"startAction = \"(\\w+)\"");
                    if (a) { action = a; break; }
                }
            }
            for (VMInfo *v in vms) {
                if ([v.vmid isEqualToString:key]) {
                    v.autostart = [action isEqualToString:@"powerOn"];
                }
            }
        }
    }

    // 快照 + 资源
    for (VMInfo *v in vms) {
        NSString *sum = sumBlocks[v.vmid] ?: @"";
        NSString *cpu = RegexFirst(sum, @"overallCpuUsage = (\\d+)");
        NSString *gm = RegexFirst(sum, @"guestMemoryUsage = (\\d+)");
        NSString *hm = RegexFirst(sum, @"hostMemoryUsage = (\\d+)");
        v.cpuMhz = cpu ? cpu.intValue : 0;
        v.guestMemMB = gm ? gm.intValue : 0;
        v.hostMemMB = hm ? hm.intValue : 0;

        NSString *snap = snapBlocks[v.vmid] ?: @"";
        NSArray *snapLines = [snap componentsSeparatedByString:@"\n"];
        NSString *curName = nil, *curId = nil, *curDate = nil;
        for (NSString *sl in snapLines) {
            NSString *nm = RegexLineFirst(sl, @"Snapshot Name\\s*:\\s*(.+)");
            NSString *sid = RegexLineFirst(sl, @"Snapshot Id\\s*:\\s*(\\d+)");
            NSString *sd = RegexLineFirst(sl, @"Snapshot Created On\\s*:\\s*(.+)");
            if (nm) curName = [nm stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (sid) curId = sid;
            if (sd) {
                curDate = [sd stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                if (curName && curId) {
                    [v.snapshots addObject:@{@"name": curName, @"id": curId, @"date": curDate}];
                }
                curName = nil; curId = nil; curDate = nil;
            }
        }
    }

    d[@"cores"] = @(cores);
    d[@"vms"] = vms;
    d[@"has_meta"] = @(asLines.count > 0 || snapBlocks.count > 0);
    return [NSMutableArray arrayWithArray:@[d]];
}

// ══════════════════════════════════════════════════════════════
// SOAP 层（模拟网页端 /sdk 接口，hostd 返回缓存数据，零进程开销）
// ══════════════════════════════════════════════════════════════
@interface AllowAllCertDelegate : NSObject <NSURLSessionDelegate>
@end
@implementation AllowAllCertDelegate
- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
}
@end

static NSString *gSoapCookie = nil;
static AllowAllCertDelegate *gCertDelegate = nil;
static NSString *gCachedTempLine = nil;
static time_t gLastTempFetch = 0;

static NSString *XMLEscape(NSString *s) {
    if (!s) return @"";
    s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return s;
}

static NSString *SOAPCall(NSString *host, int port, NSString *xmlBody, NSString **respOut, NSString **errOut) {
    *errOut = nil;
    if (!gCertDelegate) gCertDelegate = [AllowAllCertDelegate new];
    // SOAP 固定走 443（HTTPS /sdk 接口），与 SSH 端口无关
    NSString *urlStr = [NSString stringWithFormat:@"https://%@:443/sdk", host];
    NSURL *url = [NSURL URLWithString:urlStr];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
    req.HTTPMethod = @"POST";
    [req setValue:@"text/xml; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"urn:vim25/8.0.2.0" forHTTPHeaderField:@"SOAPAction"];
    if (gSoapCookie.length > 0) [req setValue:gSoapCookie forHTTPHeaderField:@"Cookie"];
    req.HTTPBody = [xmlBody dataUsingEncoding:NSUTF8StringEncoding];

    __block NSData *data = nil;
    __block NSHTTPURLResponse *httpResp = nil;
    __block NSError *nserr = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg delegate:gCertDelegate delegateQueue:nil];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        data = d; httpResp = (NSHTTPURLResponse *)r; nserr = e;
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC));
    [session finishTasksAndInvalidate];
    if (nserr) { *errOut = [NSString stringWithFormat:@"SOAP请求失败: %@", nserr.localizedDescription]; return nil; }
    NSString *resp = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (httpResp) {
        NSString *sc = httpResp.allHeaderFields[@"Set-Cookie"];
        if ([sc containsString:@"vmware_soap_session"]) {
            gSoapCookie = [[sc componentsSeparatedByString:@";"] firstObject];
        }
    }
    if (respOut) *respOut = resp;
    return resp;
}

// 登录（失败会清 cookie）
static BOOL SOAPLogin(NSString *host, int port, NSString *user, NSString *pass, NSString **errOut) {
    gSoapCookie = nil;
    NSString *body = [NSString stringWithFormat:
        @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><Login xmlns=\"urn:vim25\"><_this type=\"SessionManager\">ha-sessionmgr</_this><userName>%@</userName><password>%@</password></Login></soapenv:Body></soapenv:Envelope>",
        XMLEscape(user), XMLEscape(pass)];
    NSString *resp = nil;
    NSString *r = SOAPCall(host, port, body, &resp, errOut);
    if (!r) return NO;
    if ([r containsString:@"<faultstring>"]) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<faultstring>([^<]+)</faultstring>" options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:r options:0 range:NSMakeRange(0, r.length)];
        if (m) *errOut = [r substringWithRange:[m rangeAtIndex:1]];
        return NO;
    }
    return gSoapCookie.length > 0;
}

// 统一取数 XML：一次请求拿 VM + 主机 + 存储 + 快照
static NSString *BuildSoapFetchXML(void) {
    return
    @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><RetrievePropertiesEx xmlns=\"urn:vim25\"><_this type=\"PropertyCollector\">ha-property-collector</_this><specSet>"
    // VM
    @"<propSet><type>VirtualMachine</type><pathSet>name</pathSet><pathSet>runtime.powerState</pathSet><pathSet>summary.quickStats.overallCpuUsage</pathSet><pathSet>summary.quickStats.hostMemoryUsage</pathSet><pathSet>summary.quickStats.guestMemoryUsage</pathSet><pathSet>snapshot</pathSet></propSet>"
    // Host
    @"<propSet><type>HostSystem</type><pathSet>name</pathSet><pathSet>summary.quickStats.overallCpuUsage</pathSet><pathSet>summary.quickStats.overallMemoryUsage</pathSet><pathSet>summary.quickStats.uptime</pathSet><pathSet>hardware.memorySize</pathSet><pathSet>hardware.cpuInfo.numCpuCores</pathSet></propSet>"
    // Datastore
    @"<propSet><type>Datastore</type><pathSet>name</pathSet><pathSet>summary.capacity</pathSet><pathSet>summary.freeSpace</pathSet></propSet>"
    // AutoStart
    @"<propSet><type>HostAutoStartManager</type><pathSet>config</pathSet></propSet>"
    // objectSet 1: VM 遍历
    @"<objectSet><obj type=\"Folder\">ha-folder-root</obj><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>t1</name><type>Folder</type><path>childEntity</path><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>t2</name><type>Datacenter</type><path>vmFolder</path><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>t3</name><type>Folder</type><path>childEntity</path><skip>false</skip></selectSet></selectSet></selectSet></objectSet>"
    // objectSet 2: Host 遍历
    @"<objectSet><obj type=\"Folder\">ha-folder-root</obj><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>h1</name><type>Folder</type><path>childEntity</path><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>h2</name><type>Datacenter</type><path>hostFolder</path><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>h3</name><type>Folder</type><path>childEntity</path><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>h4</name><type>ComputeResource</type><path>host</path><skip>false</skip></selectSet></selectSet></selectSet></selectSet></objectSet>"
    // objectSet 3: Datastore 遍历
    @"<objectSet><obj type=\"Folder\">ha-folder-root</obj><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>d1</name><type>Folder</type><path>childEntity</path><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>d2</name><type>Datacenter</type><path>datastoreFolder</path><skip>false</skip><selectSet xsi:type=\"TraversalSpec\"><name>d3</name><type>Folder</type><path>childEntity</path><skip>false</skip></selectSet></selectSet></selectSet></objectSet>"
    // objectSet 4: AutoStart 管理器
    @"<objectSet><obj type=\"HostAutoStartManager\">ha-autostart-mgr</obj><skip>false</skip></objectSet>"
    @"</specSet><options><maxObjects>200</maxObjects></options></RetrievePropertiesEx></soapenv:Body></soapenv:Envelope>";
}

// 从 SOAP 响应解析全部数据 → 返回和 ParseOutput 相同结构的字典
static NSMutableDictionary *ParseSoapResponse(NSString *xml) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSMutableArray *vms = [NSMutableArray array];

    // ── VM ──
    NSRegularExpression *vmRe = [NSRegularExpression regularExpressionWithPattern:@"<obj type=\"VirtualMachine\">([^<]+)</obj>(.*?)</objects>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    [vmRe enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        NSString *vid = [xml substringWithRange:[m rangeAtIndex:1]];
        NSString *b = [xml substringWithRange:[m rangeAtIndex:2]];
        NSString *nm = RegexFirst(b, @"<name>name</name><val[^>]*>([^<]+)</val>");
        if (!nm) return;
        VMInfo *v = [VMInfo new];
        v.vmid = vid;
        v.name = nm;
        NSString *ps = RegexFirst(b, @"<name>runtime.powerState</name><val[^>]*>([^<]+)</val>");
        NSString *sl = (ps ?: @"").lowercaseString;
        v.state = [sl containsString:@"poweredon"] ? @"running" :
                  ([sl containsString:@"poweredoff"] ? @"off" :
                   ([sl containsString:@"suspended"] ? @"suspended" : @"unknown"));
        NSString *cpu = RegexFirst(b, @"<name>summary.quickStats.overallCpuUsage</name><val[^>]*>([^<]+)</val>");
        NSString *hm = RegexFirst(b, @"<name>summary.quickStats.hostMemoryUsage</name><val[^>]*>([^<]+)</val>");
        NSString *gm = RegexFirst(b, @"<name>summary.quickStats.guestMemoryUsage</name><val[^>]*>([^<]+)</val>");
        v.cpuMhz = cpu ? cpu.intValue : 0;
        v.hostMemMB = hm ? hm.intValue : 0;
        v.guestMemMB = gm ? gm.intValue : 0;
        // 快照
        if ([b containsString:@"rootSnapshotList"]) {
            NSRegularExpression *snRe = [NSRegularExpression regularExpressionWithPattern:@"<name>([^<]+)</name><description>[^<]*</description><id>(\\d+)</id><createTime>([^<]+)</createTime>" options:0 error:nil];
            [snRe enumerateMatchesInString:b options:0 range:NSMakeRange(0, b.length) usingBlock:^(NSTextCheckingResult *m2, NSMatchingFlags f2, BOOL *stop2) {
                [v.snapshots addObject:@{
                    @"name": [b substringWithRange:[m2 rangeAtIndex:1]],
                    @"id": [b substringWithRange:[m2 rangeAtIndex:2]],
                    @"date": [b substringWithRange:[m2 rangeAtIndex:3]]}];
            }];
        }
        [vms addObject:v];
    }];
    d[@"vms"] = vms;

    // ── 自启配置 ──
    // 从 HostAutoStartManager config 提取 powerInfo（key -> startAction）
    NSRegularExpression *asRe = [NSRegularExpression regularExpressionWithPattern:@"<key type=\"VirtualMachine\">(\\d+)</key>.*?<startAction>(\\w+)</startAction>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSMutableDictionary *asMap = [NSMutableDictionary dictionary];
    [asRe enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        NSString *vid = [xml substringWithRange:[m rangeAtIndex:1]];
        NSString *act = [xml substringWithRange:[m rangeAtIndex:2]];
        asMap[vid] = act;
    }];
    for (VMInfo *v in vms) {
        v.autostart = [asMap[v.vmid] isEqualToString:@"powerOn"];
    }

    // ── 主机 ──
    NSRegularExpression *hRe = [NSRegularExpression regularExpressionWithPattern:@"<obj type=\"HostSystem\">([^<]+)</obj>(.*?)</objects>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    [hRe enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        NSString *b = [xml substringWithRange:[m rangeAtIndex:2]];
        NSString *cpuMhz = RegexFirst(b, @"<name>summary.quickStats.overallCpuUsage</name><val[^>]*>([^<]+)</val>");
        NSString *memMB = RegexFirst(b, @"<name>summary.quickStats.overallMemoryUsage</name><val[^>]*>([^<]+)</val>");
        NSString *upSec = RegexFirst(b, @"<name>summary.quickStats.uptime</name><val[^>]*>([^<]+)</val>");
        NSString *memSize = RegexFirst(b, @"<name>hardware.memorySize</name><val[^>]*>([^<]+)</val>");
        NSString *cores = RegexFirst(b, @"<name>hardware.cpuInfo.numCpuCores</name><val[^>]*>([^<]+)</val>");
        NSString *hostName = RegexFirst(b, @"<name>name</name><val[^>]*>([^<]+)</val>");
        if (hostName) d[@"host_name"] = hostName;
        int coresN = cores ? cores.intValue : 1;
        d[@"cores"] = @(coresN);
        d[@"cpu_mhz"] = cpuMhz ? @(cpuMhz.doubleValue) : @0;  // 当前使用 MHz
        d[@"cpu_cores"] = @(coresN);
        // 主机 CPU 使用率（假设 2.4GHz 基准）
        double cpuPct = cpuMhz ? cpuMhz.doubleValue / (coresN * 2400.0) * 100.0 : 0;
        if (cpuPct > 100) cpuPct = 100;
        d[@"cpu_pct"] = @(cpuPct);
        double fakeLoad1 = cpuPct * coresN / 100.0;
        // 内存
        double totalMB = memSize ? memSize.doubleValue / 1024.0 / 1024.0 : 0;
        double usedMB = memMB ? memMB.doubleValue : 0;
        if (totalMB > 0) {
            d[@"vst"] = @(totalMB * 1024.0); // KB
            double freeMB = totalMB - usedMB;
            if (freeMB < 0) freeMB = 0;
            d[@"vsf"] = @(freeMB * 1024.0); // KB
        }
        // uptime 秒 → 兼容字符串 + 独立秒数字段（render 直接使用）
        int secs = upSec ? upSec.intValue : 0;
        d[@"uptime_secs"] = @(secs);
        int days = secs / 86400, hours = (secs % 86400) / 3600, mins = (secs % 3600) / 60;
        d[@"uptime"] = [NSString stringWithFormat:@"0 up %d days, %d:%02d, load average: %.2f, %.2f", days, hours, mins, fakeLoad1, fakeLoad1];
    }];

    // ── 存储（结构化：按名称/容量区分 NVMe 与 USB，NVMe 优先）──
    NSRegularExpression *dsRe = [NSRegularExpression regularExpressionWithPattern:@"<obj type=\"Datastore\">([^<]+)</obj>(.*?)</objects>" options:NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSMutableArray *dsList = [NSMutableArray array];
    [dsRe enumerateMatchesInString:xml options:0 range:NSMakeRange(0, xml.length) usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        NSString *b = [xml substringWithRange:[m rangeAtIndex:2]];
        NSString *nm = RegexFirst(b, @"<name>name</name><val[^>]*>([^<]+)</val>");
        NSString *cap = RegexFirst(b, @"<name>summary.capacity</name><val[^>]*>([^<]+)</val>");
        NSString *free = RegexFirst(b, @"<name>summary.freeSpace</name><val[^>]*>([^<]+)</val>");
        if (!nm) return;
        double capB = cap ? cap.doubleValue : 0;
        double freeB = free ? free.doubleValue : 0;
        double usedB = capB - freeB;
        if (usedB < 0) usedB = 0;
        int pct = capB > 0 ? (int)round(usedB / capB * 100) : 0;
        [dsList addObject:@{
            @"name": nm,
            @"total": @(capB),
            @"used": @(usedB),
            @"free": @(freeB),
            @"pct": @(pct)}];
    }];
    // NVMe 优先：名字含 ssd 排前；否则容量大的排前
    [dsList sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL aSsd = [a[@"name"] localizedCaseInsensitiveContainsString:@"ssd"];
        BOOL bSsd = [b[@"name"] localizedCaseInsensitiveContainsString:@"ssd"];
        if (aSsd != bSsd) return aSsd ? NSOrderedAscending : NSOrderedDescending;
        double at = [a[@"total"] doubleValue], bt = [b[@"total"] doubleValue];
        return at > bt ? NSOrderedAscending : NSOrderedDescending;
    }];
    if (dsList.count >= 1) d[@"ds1"] = dsList[0];
    if (dsList.count >= 2) d[@"ds2"] = dsList[1];

    d[@"has_meta"] = @YES;
    return d;
}

// SOAP 操作：返回 nil=成功，否则为错误信息
static NSString *SOAPOp(NSString *host, int port, NSString *xmlBody) {
    NSString *resp = nil, *err = nil;
    NSString *r = SOAPCall(host, port, xmlBody, &resp, &err);
    if (!r) return err ?: @"请求失败";
    if ([r containsString:@"<faultstring>"]) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<faultstring>([^<]+)</faultstring>" options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:r options:0 range:NSMakeRange(0, r.length)];
        if (m) return [r substringWithRange:[m rangeAtIndex:1]];
        return @"操作失败";
    }
    return nil;
}

// ══════════════════════════════════════════════════════════════
// 设置存取
// ══════════════════════════════════════════════════════════════
static NSString *SGet(NSString *key, NSString *def) {
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:key];
    return v.length > 0 ? v : def;
}
static int SGetInt(NSString *key, int def) {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v intValue] : def;
}

@interface GlassCard : UIView
@property (nonatomic, strong) UIVisualEffectView *blurView;
@property (nonatomic, strong) UIView *highlightBorder;   // 高光描边
@end



// ══════════════════════════════════════════════════════════════
// 震动反馈辅助
// ══════════════════════════════════════════════════════════════
static void HapticTap(void) {
    AudioServicesPlaySystemSound(1519);  // peek 轻震
    AudioServicesPlaySystemSound(1105);  // 叮咚提示音
}
static void HapticConfirm(void) {
    // 持续约 1 秒的强烈震动：间隔触发长震，模拟持续 1 秒
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
    });
}

// "叮咚"提示音（iOS 键盘声 1104 = Tock，1105 = 键盘声，1057 = 经典叮咚）
static void PlayDingSound(void) {
    AudioServicesPlaySystemSound(1105);  // 键盘滴答声（类似叮咚）
    // 震动 + 音效同时
    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
}
static void PlayConfirmSound(void) {
    // 完成确认：经典"叮咚"音效 + 震动
    AudioServicesPlaySystemSound(1057);  // 经典叮咚声
}

// ══════════════════════════════════════════════════════════════
// 组件：滑动确认（iOS 滑动关机样式）
// ══════════════════════════════════════════════════════════════
@interface SlideConfirmView : UIView
@property (nonatomic, strong) UIView *trackView;
@property (nonatomic, strong) UILabel *tipLabel;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) UIImageView *arrowIcon;
@property (nonatomic, copy) void (^onConfirm)(void);
@property (nonatomic) CGFloat trackMaxX;
@property (nonatomic) BOOL confirmed;
@end

@implementation SlideConfirmView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _confirmed = NO;
        // 轨道
        _trackView = [[UIView alloc] initWithFrame:self.bounds];
        _trackView.backgroundColor = [UIColor colorWithRed:0.85 green:0.87 blue:0.90 alpha:1];
        _trackView.layer.cornerRadius = frame.size.height / 2;
        _trackView.layer.masksToBounds = YES;
        [self addSubview:_trackView];
        // 提示文字
        _tipLabel = [UILabel new];
        _tipLabel.text = @"滑动确认";
        _tipLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _tipLabel.textColor = [UIColor colorWithWhite:0.4 alpha:0.9];
        _tipLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_tipLabel];
        // 滑块
        _thumbView = [[UIView alloc] initWithFrame:CGRectMake(4, 4, frame.size.height - 8, frame.size.height - 8)];
        _thumbView.backgroundColor = UIColor.whiteColor;
        _thumbView.layer.cornerRadius = (frame.size.height - 8) / 2;
        _thumbView.layer.shadowColor = [UIColor blackColor].CGColor;
        _thumbView.layer.shadowOpacity = 0.25;
        _thumbView.layer.shadowOffset = CGSizeMake(0, 1);
        _thumbView.layer.shadowRadius = 3;
        [self addSubview:_thumbView];
        // 箭头
        _arrowIcon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.right"]];
        _arrowIcon.tintColor = [UIColor BB_NEON_BLUE];
        _arrowIcon.frame = CGRectMake(0, 0, 20, 20);
        _arrowIcon.center = CGPointMake(_thumbView.bounds.size.width / 2, _thumbView.bounds.size.height / 2);
        [_thumbView addSubview:_arrowIcon];

        _trackMaxX = frame.size.width - frame.size.height + 4;

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _trackView.frame = self.bounds;
    _tipLabel.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
    _trackMaxX = self.bounds.size.width - self.bounds.size.height + 4;
    if (!_confirmed) {
        _thumbView.frame = CGRectMake(4, 4, self.bounds.size.height - 8, self.bounds.size.height - 8);
    }
}
- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (_confirmed) return;
    CGPoint t = [g translationInView:self];
    CGFloat thumbW = self.bounds.size.height - 8;
    CGFloat maxX = self.bounds.size.width - thumbW - 4;
    CGFloat x = 4 + t.x;
    if (x < 4) x = 4;
    if (x > maxX) x = maxX;
    if (g.state == UIGestureRecognizerStateChanged) {
        _thumbView.frame = CGRectMake(x, 4, thumbW, thumbW);
        // 文字跟随滑块淡出
        CGFloat progress = (x - 4) / (maxX - 4);
        _tipLabel.alpha = 1.0 - progress;
        // 箭头变色
        if (progress > 0.7) _arrowIcon.tintColor = UIColor.whiteColor;
        else _arrowIcon.tintColor = [UIColor BB_NEON_BLUE];
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled ||
               g.state == UIGestureRecognizerStateFailed) {
        if (x > maxX * 0.82) {
            // 触发确认：完整震动 + 叮咚提示音
            HapticConfirm();
            PlayConfirmSound();
            _confirmed = YES;
            [UIView animateWithDuration:0.25 animations:^{
                _thumbView.frame = CGRectMake(maxX, 4, thumbW, thumbW);
                _trackView.backgroundColor = [UIColor BB_NEON_GREEN];
                _tipLabel.alpha = 0;
            } completion:^(BOOL finished) {
                if (self.onConfirm) self.onConfirm();
            }];
        } else {
            [UIView animateWithDuration:0.25 animations:^{
                _thumbView.frame = CGRectMake(4, 4, thumbW, thumbW);
                _tipLabel.alpha = 1.0;
            }];
        }
    }
}
@end

// ══════════════════════════════════════════════════════════════
// 滑动确认弹窗控制器
// ══════════════════════════════════════════════════════════════
@interface SlideConfirmVC : UIViewController
@property (nonatomic, copy) NSString *confirmTitle;
@property (nonatomic, copy) NSString *confirmMessage;
@property (nonatomic, copy) NSString *slideText;
@property (nonatomic, copy) void (^onConfirm)(void);
@end

@implementation SlideConfirmVC {
    UIView *_cardRef;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.4];

    CGFloat cardW = self.view.bounds.size.width - 60;
    UIView *card = [[GlassCard alloc] initWithFrame:CGRectMake(30, 0, cardW, 220)];
    card.center = CGPointMake(self.view.center.x, self.view.center.y - 40);
    _cardRef = card;
    [self.view addSubview:card];

    UILabel *titleLb = [UILabel new];
    titleLb.text = self.confirmTitle ?: @"确认操作";
    titleLb.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLb.textColor = UIColor.BB_WHITE_TEXT;
    titleLb.textAlignment = NSTextAlignmentCenter;
    titleLb.frame = CGRectMake(16, 20, cardW - 32, 24);
    [card addSubview:titleLb];

    UILabel *msgLb = [UILabel new];
    msgLb.text = self.confirmMessage ?: @"";
    msgLb.font = [UIFont systemFontOfSize:13];
    msgLb.textColor = UIColor.darkGrayColor;
    msgLb.textAlignment = NSTextAlignmentCenter;
    msgLb.numberOfLines = 0;
    msgLb.frame = CGRectMake(20, 52, cardW - 40, 70);
    [card addSubview:msgLb];

    SlideConfirmView *slider = [[SlideConfirmView alloc] initWithFrame:CGRectMake(30, 140, cardW - 60, 48)];
    slider.tipLabel.text = self.slideText ?: @"滑动确认";
    __weak typeof(self) weakSelf = self;
    slider.onConfirm = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf confirmDismiss];
    };
    [card addSubview:slider];

    // 点击背景取消
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapBg)];
    tap.delegate = self;
    [self.view addGestureRecognizer:tap];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return touch.view == self.view;
}
- (void)tapBg {
    [self fadeOutDismiss];
}

// 平滑淡出关闭（背景+卡片一起渐隐，避免系统转场阴影）
- (void)fadeOutDismiss {
    [UIView animateWithDuration:0.22
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.view.alpha = 0;
        _cardRef.transform = CGAffineTransformMakeScale(0.92, 0.92);
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }];
}

// 滑动确认成功时也走淡出
- (void)confirmDismiss {
    [UIView animateWithDuration:0.18
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.view.alpha = 0;
    } completion:^(BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:^{
            if (self.onConfirm) self.onConfirm();
        }];
    }];
}
@end

// ══════════════════════════════════════════════════════════════
// 组件：玻璃卡片基类（iOS 26 Liquid Glass 质感模拟）
// ══════════════════════════════════════════════════════════════
@implementation GlassCard
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        // 纯白卡片底（与虚拟机卡片统一：白底 + 浅灰细边框 + 大圆角）
        self.backgroundColor = UIColor.whiteColor;
        self.layer.cornerRadius = 14;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithRed:0.89 green:0.91 blue:0.94 alpha:1].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.05;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 6;
    }
    return self;
}
@end

// ══════════════════════════════════════════════════════════════
// 组件：卡片
// ══════════════════════════════════════════════════════════════
@interface CardView : GlassCard
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *subLabel;
@property (nonatomic, strong) UILabel *rightLabel;   // 右上角小字（更新时间）
@end
@implementation CardView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        _titleLabel.textColor = [UIColor colorWithRed:0.39 green:0.45 blue:0.53 alpha:1];
        _valueLabel = [UILabel new];
        _valueLabel.font = [UIFont systemFontOfSize:32 weight:UIFontWeightBold];
        _valueLabel.textColor = UIColor.BB_WHITE_TEXT;
        _subLabel = [UILabel new];
        _subLabel.font = [UIFont systemFontOfSize:12];
        _subLabel.textColor = [UIColor colorWithRed:0.58 green:0.62 blue:0.68 alpha:1];
        [self addSubview:_titleLabel];
        [self addSubview:_valueLabel];
        [self addSubview:_subLabel];
        _rightLabel = [UILabel new];
        _rightLabel.font = [UIFont systemFontOfSize:10];
        _rightLabel.textColor = [UIColor BB_DARK_GRAY];
        _rightLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:_rightLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _titleLabel.frame = CGRectMake(14, 10, self.bounds.size.width - 100, 18);
    _rightLabel.frame = CGRectMake(self.bounds.size.width - 96, 10, 82, 18);
    _valueLabel.frame = CGRectMake(14, 30, self.bounds.size.width - 28, 40);
    _subLabel.frame = CGRectMake(14, 72, self.bounds.size.width - 28, 16);
}
@end

// ══════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════
// 组件：资源卡片（标题 + 数值 + 进度条 + 百分比）
// ══════════════════════════════════════════════════════════════
@interface MeterCard : GlassCard
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UILabel *pctLabel;
@property (nonatomic, strong) UIProgressView *bar;
@end
@implementation MeterCard
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        _titleLabel.textColor = [UIColor colorWithRed:0.35 green:0.4 blue:0.48 alpha:0.85];
        [self addSubview:_titleLabel];
        _valueLabel = [UILabel new];
        _valueLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        _valueLabel.textColor = UIColor.BB_WHITE_TEXT;
        [self addSubview:_valueLabel];
        _pctLabel = [UILabel new];
        _pctLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        _pctLabel.textColor = [UIColor BB_NEON_GREEN];
        _pctLabel.textAlignment = NSTextAlignmentRight;
        [self addSubview:_pctLabel];
        _bar = [UIProgressView new];
        _bar.progressTintColor = [UIColor BB_NEON_GREEN];
        _bar.trackTintColor = [UIColor colorWithWhite:0.9 alpha:0.5];
        _bar.layer.cornerRadius = 3;
        _bar.clipsToBounds = YES;
        [self addSubview:_bar];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _titleLabel.frame = CGRectMake(14, 10, self.bounds.size.width - 28, 18);
    _valueLabel.frame = CGRectMake(14, 30, self.bounds.size.width - 90, 22);
    _pctLabel.frame = CGRectMake(self.bounds.size.width - 66, 30, 52, 22);
    _bar.frame = CGRectMake(14, 58, self.bounds.size.width - 28, 6);
}
- (void)setPct:(double)pct {
    float p = (float)(pct < 0 ? 0 : (pct > 100 ? 100 : pct));
    _bar.progress = p / 100.0;
    _pctLabel.text = [NSString stringWithFormat:@"%.0f%%", p];
    if (p >= 90) {
        _bar.progressTintColor = [UIColor BB_NEON_RED];
        _pctLabel.textColor = [UIColor BB_NEON_RED];
    } else if (p >= 75) {
        _bar.progressTintColor = [UIColor BB_NEON_ORANGE];
        _pctLabel.textColor = [UIColor BB_NEON_ORANGE];
    } else {
        _bar.progressTintColor = [UIColor BB_NEON_GREEN];
        _pctLabel.textColor = [UIColor BB_NEON_GREEN];
    }
}
@end

// ══════════════════════════════════════════════════════════════
// 组件：VM 行（状态/名称/电源/重启/关机/快照/自启）
// ══════════════════════════════════════════════════════════════
@interface VMRowView : GlassCard
@property (nonatomic, strong) UILabel *iconLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *infoLabel;      // CPU/内存小字
@property (nonatomic, strong) UISwitch *powerSwitch;
@property (nonatomic, strong) UIButton *snapBtn;
@property (nonatomic, strong) UIButton *autoBtn;       // 自启开关按钮
@property (nonatomic, strong) UIButton *rebootBtn;     // 重启按钮
@property (nonatomic, copy) NSString *vmId;
@property (nonatomic, copy) void (^onToggle)(NSString *vmId, BOOL on);
@property (nonatomic, copy) void (^onSnapshot)(NSString *vmId);
@property (nonatomic, copy) void (^onAuto)(NSString *vmId, BOOL on);
@property (nonatomic, copy) void (^onReboot)(NSString *vmId);
@end
@implementation VMRowView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor whiteColor];
        _iconLabel = [UILabel new];
        _iconLabel.font = [UIFont systemFontOfSize:14];
        [self addSubview:_iconLabel];
        _nameLabel = [UILabel new];
        _nameLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _nameLabel.textColor = UIColor.BB_WHITE_TEXT;
        [self addSubview:_nameLabel];
        _infoLabel = [UILabel new];
        _infoLabel.font = [UIFont systemFontOfSize:10];
        _infoLabel.textColor = UIColor.BB_DARK_GRAY;
        [self addSubview:_infoLabel];
        _powerSwitch = [UISwitch new];
        _powerSwitch.transform = CGAffineTransformMakeScale(0.62, 0.62);
        [_powerSwitch addTarget:self action:@selector(switchChanged) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_powerSwitch];
        _snapBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _snapBtn.titleLabel.font = [UIFont systemFontOfSize:10];
        [_snapBtn setTitle:@"📸 快照" forState:UIControlStateNormal];
        _snapBtn.layer.borderWidth = 0.6;
        _snapBtn.layer.borderColor = [UIColor BB_NEON_BLUE].CGColor;
        _snapBtn.layer.cornerRadius = 6;
        [_snapBtn setTitleColor:[UIColor BB_NEON_BLUE] forState:UIControlStateNormal];
        [_snapBtn addTarget:self action:@selector(snapTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_snapBtn];
        _autoBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _autoBtn.titleLabel.font = [UIFont systemFontOfSize:10];
        [_autoBtn setTitle:@"⚡自启:关" forState:UIControlStateNormal];
        _autoBtn.layer.borderWidth = 0.6;
        _autoBtn.layer.cornerRadius = 6;
        _autoBtn.layer.borderColor = [UIColor BB_DARK_GRAY].CGColor;
        [_autoBtn setTitleColor:[UIColor BB_DARK_GRAY] forState:UIControlStateNormal];
        [_autoBtn addTarget:self action:@selector(autoTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_autoBtn];
        _rebootBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        _rebootBtn.titleLabel.font = [UIFont systemFontOfSize:10];
        [_rebootBtn setTitle:@"🔄 重启" forState:UIControlStateNormal];
        _rebootBtn.layer.borderWidth = 0.6;
        _rebootBtn.layer.cornerRadius = 6;
        _rebootBtn.layer.borderColor = [UIColor systemOrangeColor].CGColor;
        [_rebootBtn setTitleColor:[UIColor systemOrangeColor] forState:UIControlStateNormal];
        [_rebootBtn addTarget:self action:@selector(rebootTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_rebootBtn];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    _iconLabel.frame = CGRectMake(12, 12, 24, 20);
    _nameLabel.frame = CGRectMake(40, 8, self.bounds.size.width - 110, 18);
    _infoLabel.frame = CGRectMake(40, 28, self.bounds.size.width - 110, 14);
    // 电源开关右上角
    _powerSwitch.frame = CGRectMake(self.bounds.size.width - 66, 6, 51, 32);
    // 底部四个按钮并排
    CGFloat bw = (self.bounds.size.width - 24 - 12) / 3.0;  // 12*2 padding + 2*6 gap
    _snapBtn.frame = CGRectMake(12, 48, bw, 24);
    _autoBtn.frame = CGRectMake(12 + (bw + 6), 48, bw, 24);
    _rebootBtn.frame = CGRectMake(12 + (bw + 6) * 2, 48, bw, 24);
}
- (void)switchChanged {
    HapticTap();
    if (self.onToggle) self.onToggle(self.vmId, self.powerSwitch.isOn);
}
- (void)snapTapped {
    HapticTap();
    if (self.onSnapshot) self.onSnapshot(self.vmId);
}
- (void)autoTapped {
    HapticTap();
    BOOL to = ![self.autoBtn.titleLabel.text containsString:@"开"];
    if (self.onAuto) self.onAuto(self.vmId, to);
}
- (void)rebootTapped {
    HapticTap();
    if (self.onReboot) self.onReboot(self.vmId);
}
- (void)setAutoUI:(BOOL)on {
    if (on) {
        [_autoBtn setTitle:@"⚡自启:开" forState:UIControlStateNormal];
        _autoBtn.layer.borderColor = [UIColor systemGreenColor].CGColor;
        [_autoBtn setTitleColor:[UIColor systemGreenColor] forState:UIControlStateNormal];
    } else {
        [_autoBtn setTitle:@"⚡自启:关" forState:UIControlStateNormal];
        _autoBtn.layer.borderColor = [UIColor BB_DARK_GRAY].CGColor;
        [_autoBtn setTitleColor:[UIColor BB_DARK_GRAY] forState:UIControlStateNormal];
    }
}
@end

@class SettingsVC;

// 设置页接口（提前声明，供主页面引用）
@interface SettingsVC : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *hostField, *portField, *userField, *passField;
@end

// ══════════════════════════════════════════════════════════════
// 主页面
// ══════════════════════════════════════════════════════════════
@interface DashboardVC : UIViewController
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) CardView *tempCard, *cpuCard, *upCard;
@property (nonatomic, strong) UILabel *memLabel, *ds1Label, *ds2Label;
@property (nonatomic, strong) MeterCard *memCard, *ds1Card, *ds2Card;
@property (nonatomic, strong) UILabel *logLabel;
@property (nonatomic, strong) UIView *logBox;
@property (nonatomic, strong) UILabel *logTitle;
@property (nonatomic, strong) NSMutableArray *vmRows;
@property (nonatomic, strong) NSMutableArray *logs;
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic, strong) NSTimer *fullRefreshTimer;
@property (nonatomic) BOOL refreshing;
@property (nonatomic, strong) NSMutableDictionary *vmMetaCache; // vmid -> {autostart, snapshots}
@property (nonatomic, strong) AVAudioPlayer *keepAlivePlayer;
@property (nonatomic, strong) UIView *statusDot;   // 连接状态圆点
@property (nonatomic, strong) UILabel *statusDotLabel;
@property (nonatomic) BOOL connected;
@property (nonatomic) NSTimeInterval lastUpdateTime;   // 最近一次成功更新时间
@end

@implementation DashboardVC

- (void)setupBackgroundKeepAlive {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;
    [session setCategory:AVAudioSessionCategoryPlayback
             withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&err];
    [session setActive:YES error:nil];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"silence" ofType:@"wav"];
    if (!path) return;
    self.keepAlivePlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:path] error:&err];
    self.keepAlivePlayer.numberOfLoops = -1;
    self.keepAlivePlayer.volume = 0.0;
    [self.keepAlivePlayer prepareToPlay];
    [self.keepAlivePlayer play];
}

- (UIColor *)tempColor:(NSNumber *)temp {
    double t = temp ? temp.doubleValue : 0;
    if (t > 60) return [UIColor BB_NEON_RED];
    if (t >= 55) return [UIColor BB_NEON_ORANGE];
    return [UIColor BB_NEON_GREEN];
}

- (void)updateStatusDot:(BOOL)online {
    self.connected = online;
    self.statusDot.backgroundColor = online ? [UIColor systemGreenColor] : [UIColor BB_NEON_RED];
    self.statusDotLabel.text = online ? @"已连接" : @"未连接";
    self.statusDotLabel.textColor = online ? [UIColor systemGreenColor] : [UIColor BB_NEON_RED];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // 主流简洁背景：iOS 系统分组灰白
    self.view.backgroundColor = [UIColor BB_BG_COLOR;

    // 标题（纯文字，状态圆点移到右上角）
    self.title = @"ESXi 监控";

    // 左上角：连接状态圆点 + 文字
    UIView *dotView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 76, 40)];
    self.statusDot = [[UIView alloc] initWithFrame:CGRectMake(0, 13, 14, 14)];
    self.statusDot.layer.cornerRadius = 7;
    self.statusDot.backgroundColor = [UIColor BB_NEON_RED];
    [dotView addSubview:self.statusDot];
    self.statusDotLabel = [UILabel new];
    self.statusDotLabel.frame = CGRectMake(18, 9, 58, 22);
    self.statusDotLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.statusDotLabel.text = @"未连接";
    self.statusDotLabel.textColor = [UIColor BB_NEON_RED];
    [dotView addSubview:self.statusDotLabel];
    UIBarButtonItem *statusItem = [[UIBarButtonItem alloc] initWithCustomView:dotView];
    self.navigationItem.leftBarButtonItem = statusItem;

    // 右上角：设置齿轮
    UIBarButtonItem *gearItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(openSettings)];
    self.navigationItem.rightBarButtonItem = gearItem;

    self.scrollView = [UIScrollView new];
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.frame = self.view.bounds;
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    CGFloat y = 16, w = self.view.bounds.size.width - 32, gap = 12;
    CGFloat cardW = (w - gap) / 2;

    self.tempCard = [[CardView alloc] initWithFrame:CGRectMake(16, y, cardW, 96)];
    self.tempCard.titleLabel.text = @"🌡 NVMe 温度";
    [self.scrollView addSubview:self.tempCard];
    self.cpuCard  = [[CardView alloc] initWithFrame:CGRectMake(16 + cardW + gap, y, cardW, 96)];
    self.cpuCard.titleLabel.text = @"⚙ CPU 负载";
    [self.scrollView addSubview:self.cpuCard];
    y += 96 + gap;
    self.upCard = [[CardView alloc] initWithFrame:CGRectMake(16, y, w, 96)];
    self.upCard.titleLabel.text = @"⏱ 运行时间";
    self.upCard.valueLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    [self.scrollView addSubview:self.upCard];
    y += 96 + gap;

    // 内存（进度条卡片）
    UILabel *sMem = [self sectionLabelWithTitle:@"内存"];
    sMem.frame = CGRectMake(16, y, w, 20); y += 26;
    self.memCard = [[MeterCard alloc] initWithFrame:CGRectMake(16, y, w, 78)];
    self.memCard.titleLabel.text = @"系统内存";
    self.memCard.valueLabel.text = @"--";
    [self.scrollView addSubview:self.memCard];
    y += 78 + 14;

    // 存储（双进度条卡片）
    UILabel *s1 = [self sectionLabelWithTitle:@"存储"];
    s1.frame = CGRectMake(16, y, w, 20); y += 26;
    self.ds1Card = [[MeterCard alloc] initWithFrame:CGRectMake(16, y, w, 78)];
    self.ds1Card.titleLabel.text = @"NVMe 存储";
    self.ds1Card.valueLabel.text = @"--";
    [self.scrollView addSubview:self.ds1Card];
    y += 78 + 12;
    self.ds2Card = [[MeterCard alloc] initWithFrame:CGRectMake(16, y, w, 78)];
    self.ds2Card.titleLabel.text = @"USB 存储";
    self.ds2Card.valueLabel.text = @"--";
    [self.scrollView addSubview:self.ds2Card];
    y += 78 + 16;

    // 虚拟机
    UILabel *s2 = [self sectionLabelWithTitle:@"虚拟机"];
    s2.frame = CGRectMake(16, y, w, 20); y += 26;
    self.vmRows = [NSMutableArray array];
    y += 12;

    // 操作反馈（白色圆角卡片，初始隐藏）
    UIView *statusCard = [[GlassCard alloc] initWithFrame:CGRectMake(16, y, w, 44)];
    statusCard.hidden = YES;
    statusCard.tag = 9991;
    [self.scrollView addSubview:statusCard];
    self.statusLabel = [UILabel new];
    self.statusLabel.frame = CGRectMake(16, 0, w - 32, 44);
    self.statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.statusLabel.textColor = UIColor.BB_DARK_GRAY;
    self.statusLabel.text = @"";
    [statusCard addSubview:self.statusLabel];
    y += 44 + 12;

    // 主机操作（关机/重启，二次确认）
    UILabel *hostTitle = [self sectionLabelWithTitle:@"🖥 主机操作"];
    hostTitle.tag = 9999;
    hostTitle.frame = CGRectMake(16, y, w, 20); y += 26;
    UIView *hostCard = [[GlassCard alloc] initWithFrame:CGRectMake(16, y, w, 78)];
    hostCard.tag = 9998;
    // 服务器名称
    UILabel *hostNameLb = [UILabel new];
    hostNameLb.tag = 9997;
    hostNameLb.text = @"--";
    hostNameLb.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    hostNameLb.textColor = UIColor.BB_WHITE_TEXT;
    hostNameLb.textAlignment = NSTextAlignmentCenter;
    hostNameLb.frame = CGRectMake(12, 6, w - 24, 20);
    [hostCard addSubview:hostNameLb];
    UIButton *shutdownHostBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    shutdownHostBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [shutdownHostBtn setTitle:@"⏻ 关机" forState:UIControlStateNormal];
    [shutdownHostBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    shutdownHostBtn.layer.cornerRadius = 10;
    shutdownHostBtn.layer.borderWidth = 1;
    shutdownHostBtn.layer.borderColor = [UIColor systemRedColor].CGColor;
    shutdownHostBtn.frame = CGRectMake(12, 30, (w - 36) / 2, 40);
    [shutdownHostBtn addTarget:self action:@selector(confirmShutdownHost) forControlEvents:UIControlEventTouchUpInside];
    [hostCard addSubview:shutdownHostBtn];
    UIButton *rebootHostBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    rebootHostBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [rebootHostBtn setTitle:@"🔄 重启" forState:UIControlStateNormal];
    [rebootHostBtn setTitleColor:[UIColor systemOrangeColor] forState:UIControlStateNormal];
    rebootHostBtn.layer.cornerRadius = 10;
    rebootHostBtn.layer.borderWidth = 1;
    rebootHostBtn.layer.borderColor = [UIColor systemOrangeColor].CGColor;
    rebootHostBtn.frame = CGRectMake(12 + (w - 36) / 2 + 12, 30, (w - 36) / 2, 40);
    [rebootHostBtn addTarget:self action:@selector(confirmRebootHost) forControlEvents:UIControlEventTouchUpInside];
    [hostCard addSubview:rebootHostBtn];
    [self.scrollView addSubview:hostCard];
    y += 78 + 16;

    // 操作日志
    self.logTitle = [self sectionLabelWithTitle:@"📋 操作日志"];
    self.logTitle.frame = CGRectMake(16, y, w, 20); y += 26;
    self.logBox = [[GlassCard alloc] initWithFrame:CGRectMake(16, y, w, 180)];
    self.logLabel = [UILabel new];
    self.logLabel.font = [UIFont systemFontOfSize:12];
    self.logLabel.textColor = UIColor.darkGrayColor;
    self.logLabel.numberOfLines = 0;
    self.logLabel.frame = CGRectMake(12, 10, w - 24, 160);
    self.logLabel.text = @"暂无操作记录";
    [self.logBox addSubview:self.logLabel];
    [self.scrollView addSubview:self.logBox];
    self.logs = [NSMutableArray array];
    // 加载持久化日志
    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:@"esxi_op_logs"];
    if (saved.count > 0) {
        [self.logs addObjectsFromArray:saved];
        self.logLabel.text = [self.logs componentsJoinedByString:@"\n"];
    }
    y += 180 + 20;

    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y);

    [self startRefreshTimers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshNow];
}

- (UILabel *)sectionLabelWithTitle:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithRed:0.20 green:0.23 blue:0.29 alpha:1];
    [self.scrollView addSubview:l];
    return l;
}
- (UILabel *)rowLabel {
    UILabel *l = [UILabel new];
    l.font = [UIFont systemFontOfSize:13];
    l.textColor = UIColor.darkGrayColor;
    [self.scrollView addSubview:l];
    return l;
}

- (void)openSettings {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[SettingsVC new]];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)addLog:(NSString *)msg {
    if (!self.logs) self.logs = [NSMutableArray array];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    NSString *ts = [fmt stringFromDate:[NSDate date]];
    [self.logs insertObject:[NSString stringWithFormat:@"[%@] %@", ts, msg] atIndex:0];
    if (self.logs.count > 100) [self.logs removeObjectsInRange:NSMakeRange(100, self.logs.count - 100)];
    self.logLabel.text = [self.logs componentsJoinedByString:@"\n"];
    // 持久化到 NSUserDefaults（永久保存）
    [[NSUserDefaults standardUserDefaults] setObject:self.logs forKey:@"esxi_op_logs"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)refreshNow {
    // 断连检测：距上次成功更新超过 3 秒 → 立即显示断开状态（不受请求锁影响）
    NSTimeInterval nowT2 = [NSDate date].timeIntervalSince1970;
    if (self.lastUpdateTime > 0 && (nowT2 - self.lastUpdateTime) > 3.0) {
        [self updateStatusDot:NO];
        self.statusLabel.text = @"⚠️ 连接断开，无法获取数据";
        self.statusLabel.textColor = UIColor.systemRedColor;
        self.upCard.rightLabel.text = @"连接已断开";
        self.upCard.rightLabel.textColor = UIColor.systemRedColor;
    }
    [self doRefresh:NO];
}
- (void)fullRefreshNow {
    [self doRefresh:YES];
}

- (void)doRefresh:(BOOL)full {
    if (self.refreshing) return;
    self.refreshing = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        NSString *dev = SGet(@"esxi_device",
            @"t10.NVMe____KIOXIA2DEXCERIA_G2_SSD___________________20F58C00038EE38C");
        NSString *err = nil;
        NSMutableDictionary *d = nil;

        // 主链路：SOAP（网页端同款 /sdk，hostd 缓存数据，零进程开销）
        if (!gSoapCookie.length) {
            SOAPLogin(host, port, user, pass, &err);
        }
        if (gSoapCookie.length) {
            NSString *xml = nil;
            NSString *r = SOAPCall(host, port, BuildSoapFetchXML(), &xml, &err);
            if (r && ![r containsString:@"<faultstring>"]) {
                d = ParseSoapResponse(r);
            }
            // 会话失效或返回空：重置会话重新登录一次
            if (!d) {
                gSoapCookie = nil;
                if (SOAPLogin(host, port, user, pass, &err)) {
                    NSString *xml2 = nil;
                    NSString *r2 = SOAPCall(host, port, BuildSoapFetchXML(), &xml2, &err);
                    if (r2 && ![r2 containsString:@"<faultstring>"]) d = ParseSoapResponse(r2);
                }
            }
        }

        // 温度：SSH 查询（每秒刷新，持久连接内执行一条轻量 esxcli，开销极小）
        if (d) {
            time_t now = time(NULL);
            if (now - gLastTempFetch >= 1 || !gCachedTempLine) {
                NSString *tcmd = [NSString stringWithFormat:@"esxcli storage core device smart get -d '%@' 2>/dev/null | grep -i 'Drive Temperature'", dev];
                NSString *tout = SSHExec(host, port, user, pass, tcmd, &err);
                if (tout && tout.length > 0) {
                    gCachedTempLine = tout;
                    gLastTempFetch = now;
                }
            }
            if (gCachedTempLine.length > 0) d[@"temp_line"] = gCachedTempLine;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.refreshing = NO;
            if (d) {
                NSTimeInterval nowT = [NSDate date].timeIntervalSince1970;
                // 先算距上次更新的秒数，再更新时间戳
                if (weakSelf.lastUpdateTime > 0) {
                    long ago = (long)(nowT - weakSelf.lastUpdateTime);
                    weakSelf.upCard.rightLabel.text = [NSString stringWithFormat:@"%ld秒前更新", ago];
                } else {
                    weakSelf.upCard.rightLabel.text = @"刚刚更新";
                }
                weakSelf.lastUpdateTime = nowT;
                [weakSelf updateStatusDot:YES];
                [weakSelf render:d];
                weakSelf.upCard.rightLabel.textColor = [UIColor BB_NEON_GREEN];
                // 恢复连接：清掉断连提示（statusLabel 交由 render 正常逻辑处理）
                if ([weakSelf.statusLabel.text containsString:@"连接断开"]) {
                    weakSelf.statusLabel.text = @"";
                }
            } else {
                [weakSelf updateStatusDot:NO];
                // 断连反馈：状态文字 + 运行时间卡片右侧红字提示
                weakSelf.statusLabel.text = @"⚠️ 连接断开，无法获取数据";
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                weakSelf.upCard.rightLabel.text = @"连接已断开";
                weakSelf.upCard.rightLabel.textColor = UIColor.systemRedColor;
            }
        });
    });
}

- (void)render:(NSDictionary *)d {
    CGFloat w = self.view.bounds.size.width - 32;

    // 温度
    NSString *tempLine = d[@"temp_line"];
    NSArray *nums = nil;
    if (tempLine) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\d+" options:0 error:nil];
        NSMutableArray *found = [NSMutableArray array];
        [re enumerateMatchesInString:tempLine options:0 range:NSMakeRange(0, tempLine.length)
            usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
                [found addObject:[tempLine substringWithRange:m.range]];
            }];
        nums = found;
    }
    NSNumber *temp = nums.count >= 1 ? @([nums[0] intValue]) : nil;
    self.tempCard.valueLabel.text = temp ? [NSString stringWithFormat:@"%.0f°C", temp.doubleValue] : @"--";
    self.tempCard.valueLabel.textColor = [self tempColor:temp];
    self.tempCard.subLabel.text = nums.count >= 2 ? [NSString stringWithFormat:@"阈值 %@°C", nums[1]] : @"阈值 --°C";

    // CPU
    NSString *up = d[@"uptime"];
    double load1 = -1, load5 = -1;
    if (up) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"load average:\\s*([\\d.]+),\\s*([\\d.]+)" options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:up options:0 range:NSMakeRange(0, up.length)];
        if (m) {
            load1 = [[up substringWithRange:[m rangeAtIndex:1]] doubleValue];
            load5 = [[up substringWithRange:[m rangeAtIndex:2]] doubleValue];
        }
    }
    int cores = [d[@"cores"] intValue] ?: 1;
    double cpuPctD = [d[@"cpu_pct"] doubleValue];
    double cpuMhzD = [d[@"cpu_mhz"] doubleValue];
    int cpuPct = cpuPctD > 0 ? (int)round(cpuPctD) : -1;
    if (cpuPct < 0 && load1 >= 0 && cores > 0) cpuPct = (int)round(load1 / cores * 100);
    self.cpuCard.valueLabel.text = cpuPct >= 0 ? [NSString stringWithFormat:@"%d%%", cpuPct] : @"--";
    // 副标题：频率 MHz + 负载
    if (cpuMhzD > 0) {
        self.cpuCard.subLabel.text = [NSString stringWithFormat:@"%.0f MHz · 1分 %@ / 5分 %@",
            cpuMhzD, load1 >= 0 ? @(load1) : @"--", load5 >= 0 ? @(load5) : @"--"];
    } else {
        self.cpuCard.subLabel.text = [NSString stringWithFormat:@"1分钟 %@ / 5分钟 %@",
            load1 >= 0 ? @(load1) : @"--", load5 >= 0 ? @(load5) : @"--"];
    }

    // 运行时间（直接用 SOAP 秒数字段，绕开字符串解析）
    NSNumber *upSecsNum = d[@"uptime_secs"];
    if (upSecsNum && upSecsNum.intValue > 0) {
        int secs = upSecsNum.intValue;
        self.upCard.valueLabel.text = [NSString stringWithFormat:@"%d天 %d时 %d分",
            secs/86400, (secs%86400)/3600, (secs%3600)/60];
        self.upCard.subLabel.text = @"自上次重启以来";
    } else {
        // 回退：解析 uptime 字符串（兼容旧数据）
        int secs = 0;
        if (up) {
            NSRegularExpression *reDay = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\s+day" options:0 error:nil];
            NSRegularExpression *reHM = [NSRegularExpression regularExpressionWithPattern:@"(\\d+):(\\d+)" options:0 error:nil];
            NSTextCheckingResult *dm = [reDay firstMatchInString:up options:0 range:NSMakeRange(0, up.length)];
            NSTextCheckingResult *hm = [reHM firstMatchInString:up options:0 range:NSMakeRange(0, up.length)];
            if (dm) secs += [[up substringWithRange:[dm rangeAtIndex:1]] intValue] * 86400;
            if (hm) {
                secs += [[up substringWithRange:[hm rangeAtIndex:1]] intValue] * 3600
                      + [[up substringWithRange:[hm rangeAtIndex:2]] intValue] * 60;
            }
        }
        if (secs > 0) {
            self.upCard.valueLabel.text = [NSString stringWithFormat:@"%d天 %d时 %d分",
                secs/86400, (secs%86400)/3600, (secs%3600)/60];
            self.upCard.subLabel.text = @"自上次重启以来";
        } else {
            self.upCard.valueLabel.text = @"--";
            self.upCard.subLabel.text = @"";
        }
    }

    // 内存（进度条卡片）
    double vst = [d[@"vst"] doubleValue] / 1024.0, vsf = [d[@"vsf"] doubleValue] / 1024.0;
    if (vst > 0) {
        double used = vst - vsf; if (used < 0) used = 0;
        double pct = used / vst * 100.0;
        self.memCard.valueLabel.text = [NSString stringWithFormat:@"已用 %.1f GB / 共 %.1f GB",
            used / 1024.0, vst / 1024.0];
        [self.memCard setPct:pct];
    } else {
        self.memCard.valueLabel.text = @"--";
        [self.memCard setPct:0];
    }

    // 存储（双进度条卡片，ds1/ds2 为字典：{name,total,used,free,pct}）
    NSDictionary *ds1 = [d[@"ds1"] isKindOfClass:[NSDictionary class]] ? d[@"ds1"] : nil;
    NSDictionary *ds2 = [d[@"ds2"] isKindOfClass:[NSDictionary class]] ? d[@"ds2"] : nil;
    double ds1pct = ds1 ? [ds1[@"pct"] doubleValue] : 0;
    double ds2pct = ds2 ? [ds2[@"pct"] doubleValue] : 0;
    if (ds1) {
        // 容量用 1000 进制显示（2.0T / 1.0T）
        double capT = [ds1[@"total"] doubleValue] / 1000.0 / 1000.0 / 1000.0 / 1000.0;
        double usedT = [ds1[@"used"] doubleValue] / 1000.0 / 1000.0 / 1000.0 / 1000.0;
        self.ds1Card.valueLabel.text = [NSString stringWithFormat:@"已用 %.2fT / 总 %.1fT", usedT, capT];
        self.ds1Card.titleLabel.text = [NSString stringWithFormat:@"%@ 存储", ds1[@"name"]];
        [self.ds1Card setPct:ds1pct];
    } else {
        self.ds1Card.valueLabel.text = @"--";
        [self.ds1Card setPct:0];
    }
    if (ds2) {
        double capT = [ds2[@"total"] doubleValue] / 1000.0 / 1000.0 / 1000.0 / 1000.0;
        double usedT = [ds2[@"used"] doubleValue] / 1000.0 / 1000.0 / 1000.0 / 1000.0;
        self.ds2Card.valueLabel.text = [NSString stringWithFormat:@"已用 %.2fT / 总 %.1fT", usedT, capT];
        self.ds2Card.titleLabel.text = [NSString stringWithFormat:@"%@ 存储", ds2[@"name"]];
        [self.ds2Card setPct:ds2pct];
    } else {
        self.ds2Card.valueLabel.text = @"--";
        [self.ds2Card setPct:0];
    }
    if (ds1pct >= 90 || ds2pct >= 90) {
        self.statusLabel.text = @"⚠️ 磁盘空间超过 90%，请及时清理！";
        self.statusLabel.textColor = UIColor.systemRedColor;
    }

    // VM 列表
    NSArray *vms = d[@"vms"];
    BOOL hasMeta = [d[@"has_meta"] boolValue];
    if (!self.vmMetaCache) self.vmMetaCache = [NSMutableDictionary dictionary];
    if (hasMeta) {
        // 完整刷新：更新缓存
        for (VMInfo *v in vms) {
            self.vmMetaCache[v.vmid] = @{@"autostart": @(v.autostart), @"snapshots": v.snapshots ?: @[]};
        }
    } else {
        // 快速刷新：从缓存回填自启/快照
        for (VMInfo *v in vms) {
            NSDictionary *meta = self.vmMetaCache[v.vmid];
            if (meta) {
                v.autostart = [meta[@"autostart"] boolValue];
                v.snapshots = [NSMutableArray arrayWithArray:meta[@"snapshots"]];
            }
        }
    }
    for (VMRowView *row in self.vmRows) { [row removeFromSuperview]; }
    [self.vmRows removeAllObjects];
    CGFloat rowY = 0;
    for (VMInfo *v in vms) {
        VMRowView *row = [[VMRowView alloc] initWithFrame:CGRectMake(16, rowY, w, 82)];
        row.backgroundColor = [UIColor whiteColor];
        row.iconLabel.text = [v.state isEqualToString:@"running"] ? @"🟢" :
                             ([v.state isEqualToString:@"off"] ? @"⚪" :
                              ([v.state isEqualToString:@"suspended"] ? @"🟡" : @"⚫"));
        row.nameLabel.text = v.name;
        NSString *stateTxt = [v.state isEqualToString:@"running"] ? @"运行中" :
                             ([v.state isEqualToString:@"off"] ? @"已关机" :
                              ([v.state isEqualToString:@"suspended"] ? @"已挂起" : @"未知"));
        row.infoLabel.text = [NSString stringWithFormat:@"%@ · CPU %d MHz · 内存 %d MB · 快照 %lu 个",
            stateTxt, v.cpuMhz, v.hostMemMB, (unsigned long)v.snapshots.count];
        row.vmId = v.vmid;
        __weak typeof(self) weakSelf = self;
        row.onToggle = ^(NSString *vid, BOOL on) { [weakSelf toggleVM:vid on:on]; };
        row.onSnapshot = ^(NSString *vid) { [weakSelf manageSnapshot:vid]; };
        row.onAuto = ^(NSString *vid, BOOL on) { [weakSelf confirmAutoStart:vid on:on]; };
        row.onReboot = ^(NSString *vid) { [weakSelf confirmRebootVM:vid]; };
        row.powerSwitch.on = [v.state isEqualToString:@"running"];
        // 已关机的虚拟机禁用重启按钮
        row.rebootBtn.enabled = [v.state isEqualToString:@"running"];
        row.rebootBtn.alpha = [v.state isEqualToString:@"running"] ? 1.0 : 0.3;
        [row setAutoUI:v.autostart];
        [self.scrollView addSubview:row];
        [self.vmRows addObject:row];
        rowY += 92;
    }
    CGFloat vmEnd = rowY;

    // 动态重排：VM 标题起点 = 固定布局终点，VM 行从标题下方开始
    CGFloat vmStart = 16 + 96 + 12 + 96 + 12 + 26 + 78 + 14 + 26 + 78 + 12 + 78 + 16 + 26 + 26;
    for (int i = 0; i < self.vmRows.count; i++) {
        VMRowView *r = self.vmRows[i];
        r.frame = CGRectMake(16, vmStart + i * 92, w, 82);
    }
    CGFloat yAfter = vmStart + vmEnd + 10;
    UIView *statusCard2 = [self.scrollView viewWithTag:9991];
    statusCard2.frame = CGRectMake(16, yAfter, w, 44);
    self.statusLabel.frame = CGRectMake(16, 0, w - 32, 44);
    statusCard2.hidden = self.statusLabel.text.length == 0;
    yAfter += 44 + 12;
    // 主机操作：标题 + 卡片（用 tag 精确定位，避免误匹配内存/存储卡）
    UIView *hostTitleV = [self.scrollView viewWithTag:9999];
    UIView *hc = [self.scrollView viewWithTag:9998];
    if (hostTitleV) {
        hostTitleV.frame = CGRectMake(16, yAfter, w, 20);
        yAfter += 26;
    }
    if (hc) {
        hc.frame = CGRectMake(16, yAfter, w, 78);
        // 更新服务器名称
        UILabel *hnl = (UILabel *)[hc viewWithTag:9997];
        if (hnl) hnl.text = d[@"host_name"] ?: @"ESXi 主机";
        yAfter += 78 + 16;
    }
    self.logTitle.frame = CGRectMake(16, yAfter, w, 20);
    yAfter += 26;
    self.logBox.frame = CGRectMake(16, yAfter, w, 180);
    self.logLabel.frame = CGRectMake(12, 10, w - 24, 160);
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, yAfter + 180 + 20);
}

// ── 主机操作（关机/重启，二次确认 + SOAP）──
- (void)confirmShutdownHost {
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"关机";
    vc.confirmMessage = @"关闭 ESXi 主机？\n所有虚拟机将强制关机，主机停止运行！";
    vc.slideText = @"滑动关机";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf doHostOp:YES]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)confirmRebootHost {
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"重启";
    vc.confirmMessage = @"重启 ESXi 主机？\n所有虚拟机将重启，主机短暂离线！";
    vc.slideText = @"滑动重启";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf doHostOp:NO]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)doHostOp:(BOOL)shutdown {
    NSString *opName = shutdown ? @"关机" : @"重启";
    self.statusLabel.text = [NSString stringWithFormat:@"主机%@中…", opName];
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    [self addLog:[NSString stringWithFormat:@"主机%@中…", opName]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        NSString *method = shutdown ? @"ShutdownHost_Task" : @"RebootHost_Task";
        NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><%@ xmlns=\"urn:vim25\"><_this type=\"HostSystem\">ha-host</_this><force>true</force></%@></soapenv:Body></soapenv:Envelope>",
            method, method];
        if (!gSoapCookie.length) SOAPLogin(host, port, user, pass, NULL);
        NSString *opErr = SOAPOp(host, port, xml);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (opErr) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"主机%@失败：%@", opName, opErr];
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                [weakSelf addLog:[NSString stringWithFormat:@"❌ 主机%@失败：%@", opName, opErr]];
            } else {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"主机%@指令已发送", opName];
                weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
                [weakSelf addLog:[NSString stringWithFormat:@"✅ 主机%@指令已发送", opName]];
            }
            [weakSelf refreshNow];
        });
    });
}

// ── VM 开关 ──
- (void)toggleVM:(NSString *)vmId on:(BOOL)on {
    NSString *vmName = [self vmName:vmId];
    if (on) {
        // 开机也要滑动确认
        SlideConfirmVC *vc = [SlideConfirmVC new];
        vc.confirmTitle = @"开机";
        vc.confirmMessage = [NSString stringWithFormat:@"启动虚拟机 %@？", vmName];
        vc.slideText = @"滑动开机";
        __weak typeof(self) weakSelf = self;
        vc.onConfirm = ^{ [weakSelf doToggleVM:vmId on:YES name:vmName]; };
        vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
        [self presentViewController:vc animated:NO completion:nil];
        return;
    }
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"关机";
    vc.confirmMessage = [NSString stringWithFormat:@"关闭虚拟机 %@？\n关机后需手动开机恢复。", vmName];
    vc.slideText = @"滑动关机";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf doToggleVM:vmId on:NO name:vmName]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

// ── VM 重启（二次确认）──
- (void)confirmRebootVM:(NSString *)vmId {
    NSString *vmName = [self vmName:vmId];
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"重启";
    vc.confirmMessage = [NSString stringWithFormat:@"重启虚拟机 %@？\n重启会中断正在运行的服务。", vmName];
    vc.slideText = @"滑动重启";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf doRebootVM:vmId name:vmName]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)doRebootVM:(NSString *)vmId name:(NSString *)name {
    self.statusLabel.text = @"重启中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    [self addLog:[NSString stringWithFormat:@"重启虚拟机 %@…", name]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        // SOAP RebootGuest 或 ResetVM_Task；优先 ResetVM_Task（硬重启）
        NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><ResetVM_Task xmlns=\"urn:vim25\"><_this type=\"VirtualMachine\">%@</_this></ResetVM_Task></soapenv:Body></soapenv:Envelope>", vmId];
        if (!gSoapCookie.length) SOAPLogin(host, port, user, pass, NULL);
        NSString *opErr = SOAPOp(host, port, xml);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (opErr) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"重启失败：%@", opErr];
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                [weakSelf addLog:[NSString stringWithFormat:@"❌ %@ 重启失败：%@", name, opErr]];
            } else {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"%@ 重启成功", name];
                weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
                [weakSelf addLog:[NSString stringWithFormat:@"✅ %@ 重启成功", name]];
            }
            [weakSelf refreshNow];
        });
    });
}

// ── VM 关机（二次确认）──
- (void)confirmShutdownVM:(NSString *)vmId {
    NSString *vmName = [self vmName:vmId];
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"关机";
    vc.confirmMessage = [NSString stringWithFormat:@"关闭虚拟机 %@？\n关机后需手动开机恢复。", vmName];
    vc.slideText = @"滑动关机";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf doShutdownVM:vmId name:vmName]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)doShutdownVM:(NSString *)vmId name:(NSString *)name {
    self.statusLabel.text = @"关机中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    [self addLog:[NSString stringWithFormat:@"关闭虚拟机 %@…", name]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        // SOAP PowerOffVM_Task（硬关机）
        NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><PowerOffVM_Task xmlns=\"urn:vim25\"><_this type=\"VirtualMachine\">%@</_this></PowerOffVM_Task></soapenv:Body></soapenv:Envelope>", vmId];
        if (!gSoapCookie.length) SOAPLogin(host, port, user, pass, NULL);
        NSString *opErr = SOAPOp(host, port, xml);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (opErr) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"关机失败：%@", opErr];
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                [weakSelf addLog:[NSString stringWithFormat:@"❌ %@ 关机失败：%@", name, opErr]];
            } else {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"%@ 已关机", name];
                weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
                [weakSelf addLog:[NSString stringWithFormat:@"✅ %@ 已关机", name]];
            }
            [weakSelf refreshNow];
        });
    });
}

- (NSString *)vmName:(NSString *)vmId {
    for (VMRowView *row in self.vmRows) {
        if ([row.vmId isEqualToString:vmId]) return row.nameLabel.text ?: @"";
    }
    return @"";
}

- (void)doToggleVM:(NSString *)vmId on:(BOOL)on name:(NSString *)name {
    self.statusLabel.text = on ? @"开机中…" : @"关机中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    [self addLog:[NSString stringWithFormat:@"%@ 虚拟机 %@…", on ? @"开机" : @"关机", name]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        // SOAP 操作（网页端同款）
        NSString *opName = on ? @"PowerOnVM_Task" : @"PowerOffVM_Task";
        NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><%@ xmlns=\"urn:vim25\"><_this type=\"VirtualMachine\">%@</_this></%@></soapenv:Body></soapenv:Envelope>",
            opName, vmId, opName];
        if (!gSoapCookie.length) SOAPLogin(host, port, user, pass, NULL);
        NSString *opErr = SOAPOp(host, port, xml);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (opErr) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"%@失败：%@", on ? @"开机" : @"关机", opErr];
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                [weakSelf addLog:[NSString stringWithFormat:@"❌ %@ %@ 失败：%@", on ? @"开机" : @"关机", name, opErr]];
            } else {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"%@ %@ 成功", on ? @"开机" : @"关机", name];
                weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
                [weakSelf addLog:[NSString stringWithFormat:@"✅ %@ %@ 成功", on ? @"开机" : @"关机", name]];
            }
            [weakSelf refreshNow];
        });
    });
}

// ── 快照管理 ──
- (VMInfo *)vmInfoById:(NSString *)vmId {
    // 从最近一次渲染的数据拿不到，直接查行
    return nil;
}

- (void)manageSnapshot:(NSString *)vmId {
    NSString *vmName = [self vmName:vmId];
    // 从行拿快照数
    int snapCount = 0;
    for (VMRowView *row in self.vmRows) {
        if ([row.vmId isEqualToString:vmId]) {
            // infoLabel 里包含快照数，简单正则
            NSString *m = RegexFirst(row.infoLabel.text, @"快照 (\\d+) 个");
            snapCount = m ? m.intValue : 0;
            break;
        }
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"%@ 快照管理", vmName]
        message:snapCount > 0 ? [NSString stringWithFormat:@"当前 %d 个快照", snapCount] : @"暂无快照"
        preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"📸 创建新快照" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) { [self confirmCreateSnapshot:vmId]; }]];
    if (snapCount > 0) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"🔄 恢复最近快照" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) { [self revertLatestSnapshot:vmId]; }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"🗑 删除全部快照" style:UIAlertActionStyleDestructive
            handler:^(UIAlertAction *a) { [self removeAllSnapshots:vmId]; }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

// 创建快照前滑动确认
- (void)confirmCreateSnapshot:(NSString *)vmId {
    NSString *vmName = [self vmName:vmId];
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"创建快照";
    vc.confirmMessage = [NSString stringWithFormat:@"为 %@ 创建新快照？", vmName];
    vc.slideText = @"滑动创建";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf createSnapshot:vmId]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)createSnapshot:(NSString *)vmId {
    NSString *vmName = [self vmName:vmId];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"创建快照"
        message:[NSString stringWithFormat:@"为 %@ 创建快照？", vmName]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"快照名称（留空自动命名）";
        tf.font = [UIFont systemFontOfSize:13];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *a) {
            NSString *snapName = alert.textFields.firstObject.text;
            if (snapName.length == 0) {
                NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
                fmt.dateFormat = @"yyyyMMdd_HHmmss";
                snapName = [NSString stringWithFormat:@"snap_%@", [fmt stringFromDate:[NSDate date]]];
            }
            [self doSnapshot:vmId name:vmName snapName:snapName];
        }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)doSnapshot:(NSString *)vmId name:(NSString *)name snapName:(NSString *)snapName {
    self.statusLabel.text = @"快照创建中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    [self addLog:[NSString stringWithFormat:@"快照 %@ 创建中…", snapName]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        // SOAP CreateSnapshot_Task（网页端同款）
        NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><CreateSnapshot_Task xmlns=\"urn:vim25\"><_this type=\"VirtualMachine\">%@</_this><name>%@</name><description>app_snapshot</description><memory>false</memory><quiesce>false</quiesce></CreateSnapshot_Task></soapenv:Body></soapenv:Envelope>",
            vmId, XMLEscape(snapName)];
        if (!gSoapCookie.length) SOAPLogin(host, port, user, pass, NULL);
        NSString *opErr = SOAPOp(host, port, xml);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (opErr) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"快照失败：%@", opErr];
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                [weakSelf addLog:[NSString stringWithFormat:@"❌ %@ 快照失败：%@", name, opErr]];
            } else {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"快照 %@ 创建成功", snapName];
                weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
                [weakSelf addLog:[NSString stringWithFormat:@"✅ %@ 快照创建成功（%@）", name, snapName]];
            }
            [weakSelf refreshNow];
        });
    });
}

- (void)revertLatestSnapshot:(NSString *)vmId {
    NSString *vmName = [self vmName:vmId];
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"恢复快照";
    vc.confirmMessage = [NSString stringWithFormat:@"恢复 %@ 到最近快照？\n虚拟机将回到快照时的状态。", vmName];
    vc.slideText = @"滑动恢复";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{
        [weakSelf addLog:[NSString stringWithFormat:@"正在恢复 %@ 到最近快照…", vmName]];
        NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><RevertToCurrentSnapshot_Task xmlns=\"urn:vim25\"><_this type=\"VirtualMachine\">%@</_this><host xsi:nil=\"true\"/><suppressPowerOn>false</suppressPowerOn></RevertToCurrentSnapshot_Task></soapenv:Body></soapenv:Envelope>", vmId];
        [weakSelf runSOAPOp:xml success:[NSString stringWithFormat:@"✅ %@ 已恢复到最近快照", vmName]
            fail:[NSString stringWithFormat:@"❌ %@ 快照恢复失败", vmName]];
    };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)removeAllSnapshots:(NSString *)vmId {
    NSString *vmName = [self vmName:vmId];
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"删除全部快照";
    vc.confirmMessage = [NSString stringWithFormat:@"删除 %@ 的全部快照？\n此操作不可恢复！", vmName];
    vc.slideText = @"滑动删除";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{
        [weakSelf addLog:[NSString stringWithFormat:@"正在删除 %@ 全部快照…", vmName]];
        NSString *xml = [NSString stringWithFormat:
            @"<?xml version=\"1.0\"?><soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><soapenv:Body><RemoveAllSnapshots_Task xmlns=\"urn:vim25\"><_this type=\"VirtualMachine\">%@</_this></RemoveAllSnapshots_Task></soapenv:Body></soapenv:Envelope>", vmId];
        [weakSelf runSOAPOp:xml success:[NSString stringWithFormat:@"✅ %@ 全部快照已删除", vmName]
            fail:[NSString stringWithFormat:@"❌ %@ 快照删除失败", vmName]];
    };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)runSOAPOp:(NSString *)xml success:(NSString *)succ fail:(NSString *)fl {
    self.statusLabel.text = @"操作中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        if (!gSoapCookie.length) SOAPLogin(host, port, user, pass, NULL);
        NSString *opErr = SOAPOp(host, port, xml);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (opErr) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"%@：%@", fl, opErr];
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                [weakSelf addLog:[NSString stringWithFormat:@"%@：%@", fl, opErr]];
            } else {
                weakSelf.statusLabel.text = succ;
                weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
                [weakSelf addLog:succ];
            }
            [weakSelf refreshNow];
        });
    });
}

// ── 自启设置 ──
// 自启设置前滑动确认
- (void)confirmAutoStart:(NSString *)vmId on:(BOOL)on {
    NSString *vmName = [self vmName:vmId];
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = on ? @"开启自启" : @"关闭自启";
    vc.confirmMessage = [NSString stringWithFormat:@"%@ 的 ESXi 开机自启？", vmName];
    vc.slideText = on ? @"滑动开启" : @"滑动关闭";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf setAutoStart:vmId on:on]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)setAutoStart:(NSString *)vmId on:(BOOL)on {
    NSString *vmName = [self vmName:vmId];
    self.statusLabel.text = on ? @"开启自启中…" : @"关闭自启中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    [self addLog:[NSString stringWithFormat:@"%@ %@ 开机自启…", on ? @"开启" : @"关闭", vmName]];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = SGet(@"esxi_host", @"6.6.6.149");
        int port = SGetInt(@"esxi_port", 22);
        NSString *user = SGet(@"esxi_user", @"root");
        NSString *pass = SGet(@"esxi_pass", @"cuicsi:CUICSI");
        // 先启用全局 autostart，再更新单台
        NSString *act = on ? @"powerOn" : @"none";
        NSString *cmd = [NSString stringWithFormat:
            @"vim-cmd hostsvc/autostartmanager/enable_autostart 1; "
            @"vim-cmd hostsvc/autostartmanager/update_autostartentry %@ %@ 0 1 none 0 systemDefault",
            vmId, act];
        NSString *err = nil;
        SSHExecRaw(host, port, user, pass, cmd, YES, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (err && err.length > 0) {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"自启设置失败：%@", err];
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                [weakSelf addLog:[NSString stringWithFormat:@"❌ %@ 自启设置失败：%@", vmName, err]];
                for (VMRowView *row in weakSelf.vmRows) {
                    if ([row.vmId isEqualToString:vmId]) { [row setAutoUI:!on]; break; }
                }
            } else {
                weakSelf.statusLabel.text = [NSString stringWithFormat:@"%@ %@ 开机自启%@", on ? @"已开启" : @"已关闭", vmName, on ? @"" : @""];
                weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
                [weakSelf addLog:[NSString stringWithFormat:@"✅ %@ 开机自启已%@", vmName, on ? @"开启" : @"关闭"]];
                for (VMRowView *row in weakSelf.vmRows) {
                    if ([row.vmId isEqualToString:vmId]) { [row setAutoUI:on]; break; }
                }
                // 同步更新缓存（立即生效，避免刷新读到旧值横跳）
                NSMutableDictionary *meta = [weakSelf.vmMetaCache[vmId] mutableCopy] ?: [NSMutableDictionary dictionary];
                meta[@"autostart"] = @(on);
                weakSelf.vmMetaCache[vmId] = meta;
            }
            // 延迟 2.5 秒再刷新：等 ESXi autostart 配置同步完成，避免读到旧值导致按钮横跳
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf refreshNow];
            });
        });
    });
}

// 启动刷新定时器（前台）
- (void)startRefreshTimers {
    if (!self.refreshTimer) {
        self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                                           selector:@selector(refreshNow)
                                                           userInfo:nil repeats:YES];
    }
    if (!self.fullRefreshTimer) {
        self.fullRefreshTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self
                                                               selector:@selector(fullRefreshNow)
                                                               userInfo:nil repeats:YES];
    }
}

// 停止刷新定时器（后台）
- (void)stopRefreshTimers {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
    [self.fullRefreshTimer invalidate];
    self.fullRefreshTimer = nil;
}

// 强制重置所有连接（SOAP 会话 + SSH 连接），回前台时用全新会话
- (void)resetConnections {
    gSoapCookie = nil;          // 清 SOAP 会话，下次刷新重新登录
    SSHClose();                 // 关闭 SSH 连接，下次刷新重新握手
    gCachedTempLine = nil;      // 清温度缓存
    gLastTempFetch = 0;
}

// 回到前台：重置连接 + 恢复刷新 + 立即刷新一次
- (void)applicationDidBecomeActive {
    [self resetConnections];
    [self startRefreshTimers];
    [self refreshNow];
    if (self.keepAlivePlayer && !self.keepAlivePlayer.isPlaying) [self.keepAlivePlayer play];
}

// 切后台：暂停刷新
- (void)applicationDidEnterBackground {
    [self stopRefreshTimers];
}
@end

// ══════════════════════════════════════════════════════════════
// 设置页
// ══════════════════════════════════════════════════════════════
@implementation SettingsVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.97 green:0.98 blue:0.99 alpha:1];
    self.title = @"连接设置";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self action:@selector(save)];

    // 可滚动容器（版本历史很长）
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.backgroundColor = [UIColor colorWithRed:0.97 green:0.98 blue:0.99 alpha:1];
    [self.view addSubview:scroll];

    CGFloat w = self.view.bounds.size.width - 32;
    CGFloat x = 16;
    CGFloat y = 20;

    // 分组标题
    UILabel *secTitle = [UILabel new];
    secTitle.text = @"ESXi 连接信息";
    secTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    secTitle.textColor = [UIColor BB_DARK_GRAY];
    secTitle.frame = CGRectMake(x + 4, y, w, 18);
    [scroll addSubview:secTitle];
    y += 26;

    // 分组容器（圆角卡片）
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, 5 * 58 + 8)];
    card.backgroundColor = UIColor.whiteColor;
    card.layer.cornerRadius = 14;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithRed:0.89 green:0.91 blue:0.94 alpha:1].CGColor;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.04;
    card.layer.shadowOffset = CGSizeMake(0, 1);
    card.layer.shadowRadius = 4;
    [scroll addSubview:card];

    NSArray *labels = @[@"ESXi 地址", @"SSH 端口", @"用户名", @"密码", @"NVMe 设备 ID"];
    NSArray *values = @[
        SGet(@"esxi_host", @"6.6.6.149"),
        [NSString stringWithFormat:@"%d", SGetInt(@"esxi_port", 22)],
        SGet(@"esxi_user", @"root"),
        SGet(@"esxi_pass", @"cuicsi:CUICSI"),
        SGet(@"esxi_device", @"t10.NVMe____KIOXIA2DEXCERIA_G2_SSD___________________20F58C00038EE38C")];

    CGFloat rowH = 58;
    for (int i = 0; i < 5; i++) {
        CGFloat ry = 4 + i * rowH;
        // 标签（输入框上方，小号灰字）
        UILabel *lb = [UILabel new];
        lb.text = labels[i];
        lb.font = [UIFont systemFontOfSize:11];
        lb.textColor = [UIColor BB_DARK_GRAY];
        lb.frame = CGRectMake(14, ry + 6, w - 28, 14);
        [card addSubview:lb];
        // 输入框（等宽，圆角边框）
        UITextField *tf = [UITextField new];
        tf.text = values[i];
        tf.font = [UIFont systemFontOfSize:14];
        tf.borderStyle = UITextBorderStyleNone;
        tf.backgroundColor = [UIColor colorWithRed:0.96 green:0.97 blue:0.98 alpha:1];
        tf.layer.cornerRadius = 8;
        tf.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 30)];
        tf.leftViewMode = UITextFieldViewModeAlways;
        tf.frame = CGRectMake(14, ry + 22, w - 28, 30);
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        tf.delegate = self;
        [card addSubview:tf];
        if (i == 0) self.hostField = tf;
        else if (i == 1) self.portField = tf;
        else if (i == 2) self.userField = tf;
        else if (i == 3) { self.passField = tf; tf.secureTextEntry = YES; }
        // 分隔线（最后一行不加）
        if (i < 4) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(14, ry + rowH - 0.5, w - 28, 0.5)];
            sep.backgroundColor = [UIColor colorWithRed:0.93 green:0.94 blue:0.96 alpha:1];
            [card addSubview:sep];
        }
    }
    y += card.frame.size.height + 16;

    // 底部说明卡片
    UIView *tipCard = [[UIView alloc] initWithFrame:CGRectMake(x, y, w, 58)];
    tipCard.backgroundColor = [UIColor colorWithRed:0.96 green:0.98 blue:1.0 alpha:1];
    tipCard.layer.cornerRadius = 10;
    tipCard.layer.borderWidth = 1;
    tipCard.layer.borderColor = [UIColor colorWithRed:0.86 green:0.92 blue:0.98 alpha:1].CGColor;
    [scroll addSubview:tipCard];
    UILabel *tip = [UILabel new];
    tip.text = @"App 直接连接 ESXi，不经过任何中转服务。\n保存后回到首页自动生效。";
    tip.font = [UIFont systemFontOfSize:12];
    tip.textColor = [UIColor BB_DARK_GRAY];
    tip.numberOfLines = 0;
    tip.frame = CGRectMake(12, 8, w - 24, 42);
    [tipCard addSubview:tip];
    y += 58 + 20;

    // ── 版本构建历史记录 ──
    UILabel *verTitle = [UILabel new];
    verTitle.text = @"📜 版本构建历史";
    verTitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    verTitle.textColor = [UIColor BB_DARK_GRAY];
    verTitle.frame = CGRectMake(x + 4, y, w, 18);
    [scroll addSubview:verTitle];
    y += 26;

    // 版本数据（最新在前）
    NSArray *versions = @[
        @{@"ver": @"v2.0.6", @"date": @"2026-08-07", @"log": @"移除压力测试（避免CPU持续100%）、体检加进度条+完成通知"},
        @{@"ver": @"v2.0.0", @"date": @"2026-08-07", @"log": @"V 重构：新增工具箱Tab（网络体检/压力测试/设备通知）、智能命名、三Tab布局"},
        @{@"ver": @"v1.1.5", @"date": @"2026-08-06", @"log": @"修复重启后运行时间不显示、IP历史记录逻辑"},
        @{@"ver": @"v1.1.4", @"date": @"2026-08-06", @"log": @"OpenWrt页去掉设备列表和操作日志，改为连接设备数量卡片"},
        @{@"ver": @"v1.1.3", @"date": @"2026-08-06", @"log": @"打开App瞬间并行连接ESXi+OpenWrt，设备列表实时刷新"},
        @{@"ver": @"v1.1.2", @"date": @"2026-08-06", @"log": @"排查确认设备流量无法100%准确，移除设备上传/下载显示"},
        @{@"ver": @"v1.1.1", @"date": @"2026-08-06", @"log": @"OpenWrt运行时间加更新时间提示，设备无流量不显示"},
        @{@"ver": @"v1.1.0", @"date": @"2026-08-06", @"log": @"外网流量改用内核计数器累计，绝对准确"},
        @{@"ver": @"v1.0.9", @"date": @"2026-08-06", @"log": @"修复运行时间显示（只显示3天00，小时丢失）"},
        @{@"ver": @"v1.0.8", @"date": @"2026-08-06", @"log": @"内存占用改为(total-available)/total口径，与其他监控一致"},
        @{@"ver": @"v1.0.7", @"date": @"2026-08-06", @"log": @"设备列表按上传流量从高到低排序"},
        @{@"ver": @"v1.0.6", @"date": @"2026-08-06", @"log": @"修复设备流量显示为0（改用路由器端解析脚本）"},
        @{@"ver": @"v1.0.5", @"date": @"2026-08-06", @"log": @"每台设备独立卡片+当月流量（上传/下载）"},
        @{@"ver": @"v1.0.4", @"date": @"2026-08-06", @"log": @"修复CPU显示0+公网IP上次记录"},
        @{@"ver": @"v1.0.3", @"date": @"2026-08-06", @"log": @"修复内存数值显示错误+外网流量改用文本解析"},
        @{@"ver": @"v1.0.2", @"date": @"2026-08-06", @"log": @"修复外网流量显示+日志与设备列表重叠"},
        @{@"ver": @"v1.0.1", @"date": @"2026-08-06", @"log": @"移除插件功能、修复卡顿、修复公网IP和流量显示"},
        @{@"ver": @"v1.0.0", @"date": @"2026-08-06", @"log": @"V 首版：ESXi+OpenWrt双Tab，家庭设备控制中心"},
        @{@"ver": @"v3.6.6", @"date": @"2026-08-06", @"log": @"修复长时间后台后回前台只显示温度，强制重置连接重新拉取"},
        @{@"ver": @"v3.6.5", @"date": @"2026-08-06", @"log": @"后台运行暂停刷新，回到前台自动恢复刷新"},
        @{@"ver": @"v3.6.4", @"date": @"2026-08-06", @"log": @"修复自启开关确认后反复横跳，延迟刷新一次到位"},
        @{@"ver": @"v3.6.3", @"date": @"2026-08-06", @"log": @"版本构建历史同步最新"},
        @{@"ver": @"v3.6.2", @"date": @"2026-08-06", @"log": @"确认/完成加叮咚提示音；设置页密码隐藏"},
        @{@"ver": @"v3.6.1", @"date": @"2026-08-06", @"log": @"滑动确认改完成后强震1秒；设置页版本构建历史"},
        @{@"ver": @"v3.6.0", @"date": @"2026-08-06", @"log": @"震动反馈版：所有按钮点击带震动；滑动确认完成后持续1秒强震"},
        @{@"ver": @"v3.5.5", @"date": @"2026-08-06", @"log": @"修复内存排版错位、主机操作区消失（tag精确定位）"},
        @{@"ver": @"v3.5.4", @"date": @"2026-08-06", @"log": @"主机操作区显示服务器名称"},
        @{@"ver": @"v3.5.3", @"date": @"2026-08-06", @"log": @"二次确认退出改平滑淡出，去掉阴影下落"},
        @{@"ver": @"v3.5.2", @"date": @"2026-08-06", @"log": @"开机/快照/自启全加滑动确认，移除VM行关机按钮"},
        @{@"ver": @"v3.5.1", @"date": @"2026-08-06", @"log": @"所有二次确认改为iOS滑动确认样式"},
        @{@"ver": @"v3.5.0", @"date": @"2026-08-06", @"log": @"新增主机操作区：主机关机/重启（二次确认）"},
        @{@"ver": @"v3.4.5", @"date": @"2026-08-06", @"log": @"所有卡片统一为虚拟机同款纯白样式"},
        @{@"ver": @"v3.4.4", @"date": @"2026-08-06", @"log": @"简洁浅色背景 + 所有显示元素卡片化"},
        @{@"ver": @"v3.4.3", @"date": @"2026-08-06", @"log": @"恢复深色渐变背景，衬托玻璃卡片质感"},
        @{@"ver": @"v3.4.2", @"date": @"2026-08-06", @"log": @"状态卡片毛玻璃 + 每台虚拟机独立玻璃卡片"},
        @{@"ver": @"v3.4.1", @"date": @"2026-08-06", @"log": @"去除深色渐变背景，保留玻璃卡片"},
        @{@"ver": @"v3.4.0", @"date": @"2026-08-06", @"log": @"iOS 26 动态玻璃质感全新外观"},
        @{@"ver": @"v3.3.7", @"date": @"2026-08-06", @"log": @"设置页布局美化（分组卡片式）"},
        @{@"ver": @"v3.3.6", @"date": @"2026-08-06", @"log": @"修复存储容量显示（NVMe 2T/USB 1T 正确区分）"},
        @{@"ver": @"v3.3.5", @"date": @"2026-08-06", @"log": @"修复恢复连接后断连提示残留"},
        @{@"ver": @"v3.3.4", @"date": @"2026-08-06", @"log": @"修复断连无反应，3秒内识别断开状态"},
        @{@"ver": @"v3.3.3", @"date": @"2026-08-06", @"log": @"运行时间卡片加更新时间提示 + 断连明确反馈"},
        @{@"ver": @"v3.3.2", @"date": @"2026-08-06", @"log": @"修复开机自启点击无效，实时同步状态"},
        @{@"ver": @"v3.3.1", @"date": @"2026-08-06", @"log": @"CPU卡片加频率百分比 + 修复VM行按钮重叠"},
        @{@"ver": @"v3.3.0", @"date": @"2026-08-06", @"log": @"内存/存储进度条卡片 + VM重启/关机按钮（二次确认）"},
        @{@"ver": @"v3.2.2", @"date": @"2026-08-06", @"log": @"状态图标移至左上角、温度每秒更新"},
        @{@"ver": @"v3.2.1", @"date": @"2026-08-06", @"log": @"状态图标右上角、每秒刷新、修复运行时间"},
        @{@"ver": @"v3.2.0", @"date": @"2026-08-06", @"log": @"改用网页端SOAP协议取数，不频繁执行SSH命令"},
        @{@"ver": @"v3.1.0", @"date": @"2026-08-06", @"log": @"去刷新图标、日志持久化、ESXi CPU占用优化"},
        @{@"ver": @"v3.0.1", @"date": @"2026-08-06", @"log": @"去除温度曲线/网络流量，修复运行时间空白"},
        @{@"ver": @"v3.0.0", @"date": @"2026-08-06", @"log": @"七功能版：快照管理/自启/连接状态/温度曲线/磁盘预警/VM资源/网络流量"},
        @{@"ver": @"v2.5.1", @"date": @"2026-08-06", @"log": @"修复操作日志与虚拟机重叠"},
        @{@"ver": @"v2.5.0", @"date": @"2026-08-06", @"log": @"新增快照按钮 + 操作日志"},
        @{@"ver": @"v2.4.0", @"date": @"2026-08-06", @"log": @"去掉转圈和提示文字，后台静默刷新"},
        @{@"ver": @"v2.3.0", @"date": @"2026-08-06", @"log": @"已关闭通知，改为每秒实时更新"},
        @{@"ver": @"v2.2.0", @"date": @"2026-08-06", @"log": @"SSH持久连接 + 虚拟机手动开关"},
        @{@"ver": @"v2.1.0", @"date": @"2026-08-06", @"log": @"内存/VM状态/3秒刷新 三个问题修复"},
        @{@"ver": @"v2.0.2", @"date": @"2026-08-06", @"log": @"改用keyboard-interactive认证修复SSH认证失败"},
        @{@"ver": @"v2.0.1", @"date": @"2026-08-06", @"log": @"修复卡片不显示问题（addSubview遗漏）"},
        @{@"ver": @"v2.0.0", @"date": @"2026-08-06", @"log": @"独立直连版：内置SSH直连ESXi，零中转"},
        @{@"ver": @"v1.4.0", @"date": @"2026-07-xx", @"log": @"初始版：WebView壳 + 路由器中转取数"},
    ];

    for (NSDictionary *v in versions) {
        // 版本卡片
        UIView *vCard = [[GlassCard alloc] initWithFrame:CGRectMake(x, y, w, 62)];
        UILabel *verLb = [UILabel new];
        verLb.text = v[@"ver"];
        verLb.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        verLb.textColor = [UIColor BB_NEON_BLUE];
        verLb.frame = CGRectMake(14, 8, 80, 20);
        [vCard addSubview:verLb];
        UILabel *dateLb = [UILabel new];
        dateLb.text = v[@"date"];
        dateLb.font = [UIFont systemFontOfSize:11];
        dateLb.textColor = [UIColor BB_DARK_GRAY];
        dateLb.textAlignment = NSTextAlignmentRight;
        dateLb.frame = CGRectMake(w - 90, 8, 76, 18);
        [vCard addSubview:dateLb];
        UILabel *logLb = [UILabel new];
        logLb.text = v[@"log"];
        logLb.font = [UIFont systemFontOfSize:12];
        logLb.textColor = UIColor.darkGrayColor;
        logLb.numberOfLines = 0;
        logLb.frame = CGRectMake(14, 30, w - 28, 26);
        [vCard addSubview:logLb];
        [scroll addSubview:vCard];
        y += 62 + 8;
    }

    scroll.contentSize = CGSizeMake(self.view.bounds.size.width, y + 30);
}
- (void)save {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:self.hostField.text forKey:@"esxi_host"];
    [ud setObject:@([self.portField.text intValue]) forKey:@"esxi_port"];
    [ud setObject:self.userField.text forKey:@"esxi_user"];
    [ud setObject:self.passField.text forKey:@"esxi_pass"];
    [ud synchronize];
    [self dismissViewControllerAnimated:YES completion:nil];
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
@end

// ══════════════════════════════════════════════════════════════
// OpenWrt SSH 层（独立会话，与 ESXi 互不干扰）
// ══════════════════════════════════════════════════════════════
static pthread_mutex_t gWrtLock = PTHREAD_MUTEX_INITIALIZER;
static int gWrtSock = -1;
static LIBSSH2_SESSION *gWrtSession = NULL;
static NSString *gWrtHost = nil, *gWrtUser = nil, *gWrtPass = nil;
static int gWrtPort = 22;
static char gWrtKbdPass[512];

static void WrtKbdIntCallback(const char *name, int name_len,
                              const char *instruction, int instruction_len,
                              int num_prompts,
                              const LIBSSH2_USERAUTH_KBDINT_PROMPT *prompts,
                              LIBSSH2_USERAUTH_KBDINT_RESPONSE *responses,
                              void **abstract) {
    if (num_prompts <= 0) return;
    for (int i = 0; i < num_prompts; i++) {
        responses[i].text = strdup(gWrtKbdPass);
        responses[i].length = (unsigned int)strlen(gWrtKbdPass);
    }
}

static void WrtSSHClose(void) {
    if (gWrtSession) {
        libssh2_session_disconnect(gWrtSession, "bye");
        libssh2_session_free(gWrtSession);
        gWrtSession = NULL;
    }
    if (gWrtSock >= 0) { close(gWrtSock); gWrtSock = -1; }
}

static BOOL WrtSSHEnsure(NSString *host, int port, NSString *user, NSString *pass, NSString **errOut) {
    *errOut = nil;
    if (gWrtSock >= 0 && gWrtSession &&
        [gWrtHost isEqualToString:host] && gWrtPort == port &&
        [gWrtUser isEqualToString:user] && [gWrtPass isEqualToString:pass]) {
        return YES;
    }
    WrtSSHClose();
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) { *errOut = @"socket 创建失败"; return NO; }
    struct sockaddr_in sin; memset(&sin, 0, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host.UTF8String, &sin.sin_addr) != 1) {
        struct hostent *he = gethostbyname(host.UTF8String);
        if (!he) { close(sock); *errOut = @"主机解析失败"; return NO; }
        memcpy(&sin.sin_addr, he->h_addr, he->h_length);
    }
    struct timeval tv = {15, 0};
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    if (connect(sock, (struct sockaddr *)&sin, sizeof(sin)) != 0) {
        close(sock); *errOut = @"连接路由器失败（网络不通）"; return NO;
    }
    LIBSSH2_SESSION *session = libssh2_session_init();
    if (!session) { close(sock); *errOut = @"SSH 初始化失败"; return NO; }
    libssh2_session_set_timeout(session, 15000);
    if (libssh2_session_handshake(session, sock) != 0) {
        *errOut = @"SSH 握手失败";
        libssh2_session_free(session); close(sock); return NO;
    }
    int auth_rc = -1;
    snprintf(gWrtKbdPass, sizeof(gWrtKbdPass), "%s", pass.UTF8String ?: "");
    auth_rc = libssh2_userauth_keyboard_interactive_ex(session, user.UTF8String,
                                                       (unsigned int)strlen(user.UTF8String),
                                                       &WrtKbdIntCallback);
    if (auth_rc != 0) {
        auth_rc = libssh2_userauth_password(session, user.UTF8String, pass.UTF8String);
    }
    if (auth_rc != 0) {
        *errOut = @"SSH 认证失败（账号密码错误）";
        libssh2_session_disconnect(session, "auth failed");
        libssh2_session_free(session); close(sock); return NO;
    }
    gWrtSock = sock; gWrtSession = session;
    gWrtHost = host; gWrtPort = port; gWrtUser = user; gWrtPass = pass;
    return YES;
}

static NSString *WrtSSHExec(NSString *host, int port, NSString *user, NSString *pass,
                            NSString *cmd, BOOL allowEmpty, NSString **errOut) {
    *errOut = nil;
    pthread_mutex_lock(&gWrtLock);
    NSString *result = nil;
    if (!WrtSSHEnsure(host, port, user, pass, errOut)) {
        pthread_mutex_unlock(&gWrtLock);
        return nil;
    }
    LIBSSH2_CHANNEL *channel = libssh2_channel_open_session(gWrtSession);
    if (!channel) {
        *errOut = @"SSH 通道打开失败"; WrtSSHClose();
        pthread_mutex_unlock(&gWrtLock); return nil;
    }
    if (libssh2_channel_exec(channel, cmd.UTF8String) != 0) {
        *errOut = @"命令执行失败";
        libssh2_channel_free(channel); WrtSSHClose();
        pthread_mutex_unlock(&gWrtLock); return nil;
    }
    NSMutableData *outData = [NSMutableData data];
    char buf[16384]; ssize_t n;
    while ((n = libssh2_channel_read(channel, buf, sizeof(buf))) > 0) {
        [outData appendBytes:buf length:(NSUInteger)n];
    }
    if (n < 0) {
        libssh2_channel_free(channel); WrtSSHClose();
        *errOut = @"SSH 读取失败（连接中断）";
        pthread_mutex_unlock(&gWrtLock); return nil;
    }
    while (libssh2_channel_read_stderr(channel, buf, sizeof(buf)) > 0) {}
    libssh2_channel_send_eof(channel);
    libssh2_channel_wait_eof(channel);
    libssh2_channel_close(channel);
    libssh2_channel_free(channel);
    if (outData.length == 0 && !allowEmpty) {
        *errOut = @"无返回数据";
        pthread_mutex_unlock(&gWrtLock); return nil;
    }
    result = [[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding];
    pthread_mutex_unlock(&gWrtLock);
    return result;
}

// ══════════════════════════════════════════════════════════════
// OpenWrt 控制页
// ══════════════════════════════════════════════════════════════
// ══════════════════════════════════════════════════════════════
// 网速仪表盘（双弧线：蓝=下载 绿=上传）
// ══════════════════════════════════════════════════════════════
@interface SpeedGaugeView : UIView
@property (nonatomic, strong) UILabel *dlLabel;    // 下载数值
@property (nonatomic, strong) UILabel *ulLabel;    // 上传数值
@property (nonatomic, strong) UILabel *dlTitle;
@property (nonatomic, strong) UILabel *ulTitle;
@property (nonatomic) CGFloat dlRatio;   // 0-1
@property (nonatomic) CGFloat ulRatio;
@end
@implementation SpeedGaugeView
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor whiteColor];
        self.layer.cornerRadius = 14;
        self.layer.borderWidth = 0.5;
        self.layer.borderColor = [UIColor colorWithRed:0.89 green:0.91 blue:0.94 alpha:1].CGColor;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.05;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowRadius = 6;

        _dlTitle = [UILabel new];
        _dlTitle.text = @"↓ 下载";
        _dlTitle.font = [UIFont systemFontOfSize:11];
        _dlTitle.textColor = [UIColor BB_DARK_GRAY];
        _dlTitle.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_dlTitle];

        _dlLabel = [UILabel new];
        _dlLabel.text = @"--";
        _dlLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
        _dlLabel.textColor = [UIColor BB_NEON_BLUE];
        _dlLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_dlLabel];

        _ulTitle = [UILabel new];
        _ulTitle.text = @"↑ 上传";
        _ulTitle.font = [UIFont systemFontOfSize:11];
        _ulTitle.textColor = [UIColor BB_DARK_GRAY];
        _ulTitle.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_ulTitle];

        _ulLabel = [UILabel new];
        _ulLabel.text = @"--";
        _ulLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
        _ulLabel.textColor = [UIColor BB_NEON_GREEN];
        _ulLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_ulLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat half = self.bounds.size.width / 2;
    _dlTitle.frame = CGRectMake(0, 16, half, 16);
    _dlLabel.frame = CGRectMake(0, 36, half, 30);
    _ulTitle.frame = CGRectMake(half, 16, half, 16);
    _ulLabel.frame = CGRectMake(half, 36, half, 30);
}
- (void)drawRect:(CGRect)rect {
    [super drawRect:rect];
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    // 下载弧线（左半圆，蓝色）
    CGFloat cx = rect.size.width * 0.25, cy = rect.size.height * 0.5;
    CGFloat r = rect.size.width * 0.22;
    CGContextSetLineWidth(ctx, 6);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    // 轨道
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.92 green:0.94 blue:0.96 alpha:1].CGColor);
    CGContextAddArc(ctx, cx, cy, r, M_PI, 2*M_PI, 0);
    CGContextStrokePath(ctx);
    // 进度
    CGContextSetStrokeColorWithColor(ctx, [UIColor BB_NEON_BLUE].CGColor);
    CGContextAddArc(ctx, cx, cy, r, M_PI, M_PI + self.dlRatio * M_PI, 0);
    CGContextStrokePath(ctx);
    // 上传弧线（右半圆，绿色）
    cx = rect.size.width * 0.75;
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithRed:0.92 green:0.94 blue:0.96 alpha:1].CGColor);
    CGContextAddArc(ctx, cx, cy, r, 0, M_PI, 0);
    CGContextStrokePath(ctx);
    CGContextSetStrokeColorWithColor(ctx, [UIColor systemGreenColor].CGColor);
    CGContextAddArc(ctx, cx, cy, r, 0, self.ulRatio * M_PI, 0);
    CGContextStrokePath(ctx);
}
- (void)setSpeedDl:(double)dl ul:(double)ul {
    // 值单位 byte/s，映射 0-100Mbps 到比例
    double dlMbps = dl * 8 / 1000000.0;
    double ulMbps = ul * 8 / 1000000.0;
    self.dlRatio = MIN(dlMbps / 100.0, 1.0);
    self.ulRatio = MIN(ulMbps / 100.0, 1.0);
    self.dlLabel.text = [NSString stringWithFormat:@"%.1f", dlMbps];
    self.ulLabel.text = [NSString stringWithFormat:@"%.1f", ulMbps];
    [self setNeedsDisplay];
}
@end

@interface OpenWrtVC : UIViewController
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) CardView *tempCard, *loadCard, *upCard;
@property (nonatomic, strong) SpeedGaugeView *speedGauge;
@property (nonatomic, strong) MeterCard *memCard, *diskCard;
@property (nonatomic, strong) CardView *trafficCard;
@property (nonatomic, strong) UILabel *trafficVal, *trafficSub;
@property (nonatomic, strong) CardView *ipCard;
@property (nonatomic, strong) UILabel *ipVal, *ipSub;
@property (nonatomic, strong) UIView *hostCard;
@property (nonatomic, strong) NSMutableArray *deviceRows;   // 设备行（保留）
@property (nonatomic, strong) UIView *deviceBox;
@property (nonatomic, strong) UILabel *devCountLabel;   // 设备数量
@property (nonatomic, strong) NSTimer *refreshTimer;
@property (nonatomic) BOOL refreshing;
@property (nonatomic) BOOL connected;
@property (nonatomic, strong) UILabel *statusDot;
@property (nonatomic, strong) UILabel *statusDotLabel;
@property (nonatomic) NSTimeInterval lastUpdateTime;
@property (nonatomic, strong) NSArray *lastDevices;   // 最近一次设备列表
@property (nonatomic) unsigned long long lastRxCounter;
@property (nonatomic) unsigned long long lastTxCounter;
@property (nonatomic) NSTimeInterval lastCounterTime;
@property (nonatomic, strong) AVAudioPlayer *keepAlivePlayer;
@end

@implementation OpenWrtVC

- (UIColor *)tempColor:(NSNumber *)temp {
    double t = temp ? temp.doubleValue : 0;
    if (t > 75) return [UIColor BB_NEON_RED];
    if (t >= 65) return [UIColor BB_NEON_ORANGE];
    return [UIColor BB_NEON_GREEN];
}

- (void)updateStatusDot:(BOOL)online {
    self.connected = online;
    self.statusDot.backgroundColor = online ? [UIColor systemGreenColor] : [UIColor BB_NEON_RED];
    self.statusDotLabel.text = online ? @"已连接" : @"未连接";
    self.statusDotLabel.textColor = online ? [UIColor systemGreenColor] : [UIColor BB_NEON_RED];
}

- (void)addLog:(NSString *)msg {
    // 操作日志已移除，仅在状态栏显示
    self.statusLabel.text = msg;
    self.statusLabel.textColor = UIColor.BB_DARK_GRAY;
}

- (UILabel *)sectionLabelWithTitle:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithRed:0.20 green:0.23 blue:0.29 alpha:1];
    [self.scrollView addSubview:l];
    return l;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor BB_BG_COLOR;
    self.title = @"OpenWrt";

    // 左上角状态
    UIView *dotView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 76, 40)];
    self.statusDot = [[UIView alloc] initWithFrame:CGRectMake(0, 13, 14, 14)];
    self.statusDot.layer.cornerRadius = 7;
    self.statusDot.backgroundColor = [UIColor BB_NEON_RED];
    [dotView addSubview:self.statusDot];
    self.statusDotLabel = [UILabel new];
    self.statusDotLabel.frame = CGRectMake(18, 9, 58, 22);
    self.statusDotLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.statusDotLabel.text = @"未连接";
    self.statusDotLabel.textColor = [UIColor BB_NEON_RED];
    [dotView addSubview:self.statusDotLabel];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:dotView];

    self.scrollView = [UIScrollView new];
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.frame = self.view.bounds;
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    CGFloat y = 16, w = self.view.bounds.size.width - 32, gap = 12;
    CGFloat cardW = (w - gap) / 2;

    // 网速仪表盘（页面顶部）
    UILabel *sGauge = [self sectionLabelWithTitle:@"📊 实时网速"];
    sGauge.frame = CGRectMake(16, y, w, 20); y += 26;
    self.speedGauge = [[SpeedGaugeView alloc] initWithFrame:CGRectMake(16, y, w, 90)];
    [self.scrollView addSubview:self.speedGauge];
    y += 90 + 14;

    self.tempCard = [[CardView alloc] initWithFrame:CGRectMake(16, y, cardW, 96)];
    self.tempCard.titleLabel.text = @"🌡 CPU 温度";
    [self.scrollView addSubview:self.tempCard];
    self.loadCard = [[CardView alloc] initWithFrame:CGRectMake(16 + cardW + gap, y, cardW, 96)];
    self.loadCard.titleLabel.text = @"📊 CPU 负载";
    [self.scrollView addSubview:self.loadCard];
    y += 96 + gap;
    self.upCard = [[CardView alloc] initWithFrame:CGRectMake(16, y, w, 96)];
    self.upCard.titleLabel.text = @"⏱ 运行时间";
    self.upCard.valueLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    [self.scrollView addSubview:self.upCard];
    y += 96 + gap;

    // 内存
    UILabel *sMem = [self sectionLabelWithTitle:@"内存"];
    sMem.frame = CGRectMake(16, y, w, 20); y += 26;
    self.memCard = [[MeterCard alloc] initWithFrame:CGRectMake(16, y, w, 78)];
    self.memCard.titleLabel.text = @"系统内存";
    self.memCard.valueLabel.text = @"--";
    [self.scrollView addSubview:self.memCard];
    y += 78 + 14;

    // 硬盘
    UILabel *sDisk = [self sectionLabelWithTitle:@"硬盘空间"];
    sDisk.frame = CGRectMake(16, y, w, 20); y += 26;
    self.diskCard = [[MeterCard alloc] initWithFrame:CGRectMake(16, y, w, 78)];
    self.diskCard.titleLabel.text = @"Overlay 存储";
    self.diskCard.valueLabel.text = @"--";
    [self.scrollView addSubview:self.diskCard];
    y += 78 + 14;

    // 外网流量 (vnstat)
    UILabel *sTraffic = [self sectionLabelWithTitle:@"📶 外网流量 (vnstat)"];
    sTraffic.frame = CGRectMake(16, y, w, 20); y += 26;
    self.trafficCard = [[CardView alloc] initWithFrame:CGRectMake(16, y, w, 92)];
    self.trafficCard.titleLabel.text = @"pppoe-wan 外网";
    self.trafficCard.valueLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.trafficVal = self.trafficCard.valueLabel;
    self.trafficSub = self.trafficCard.subLabel;
    self.trafficVal.text = @"--";
    self.trafficSub.text = @"";
    [self.scrollView addSubview:self.trafficCard];
    y += 92 + 14;

    // 公网 IP 记录
    UILabel *sIp = [self sectionLabelWithTitle:@"🌐 公网 IP"];
    sIp.frame = CGRectMake(16, y, w, 20); y += 26;
    self.ipCard = [[CardView alloc] initWithFrame:CGRectMake(16, y, w, 92)];
    self.ipCard.titleLabel.text = @"IP 记录";
    self.ipCard.valueLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    self.ipVal = self.ipCard.valueLabel;
    self.ipSub = self.ipCard.subLabel;
    self.ipVal.text = @"--";
    self.ipSub.text = @"";
    [self.scrollView addSubview:self.ipCard];
    y += 92 + 14;

    // 主机操作
    UILabel *sHost = [self sectionLabelWithTitle:@"🖥 主机操作"];
    sHost.frame = CGRectMake(16, y, w, 20); y += 26;
    self.hostCard = [[GlassCard alloc] initWithFrame:CGRectMake(16, y, w, 56)];
    self.hostCard.tag = 8898;
    UIButton *rebootBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    rebootBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [rebootBtn setTitle:@"🔄 重启路由器" forState:UIControlStateNormal];
    [rebootBtn setTitleColor:[UIColor systemOrangeColor] forState:UIControlStateNormal];
    rebootBtn.layer.cornerRadius = 10;
    rebootBtn.layer.borderWidth = 1;
    rebootBtn.layer.borderColor = [UIColor systemOrangeColor].CGColor;
    rebootBtn.frame = CGRectMake(12, 8, w - 24, 40);
    [rebootBtn addTarget:self action:@selector(confirmRebootWrt) forControlEvents:UIControlEventTouchUpInside];
    [self.hostCard addSubview:rebootBtn];
    [self.scrollView addSubview:self.hostCard];
    y += 56 + 16;

    // 连接设备数量卡片
    UILabel *sDev = [self sectionLabelWithTitle:@"🔗 连接设备"];
    sDev.frame = CGRectMake(16, y, w, 20); y += 26;
    self.deviceBox = [[GlassCard alloc] initWithFrame:CGRectMake(16, y, w, 78)];
    self.deviceBox.tag = 8897;
    [self.scrollView addSubview:self.deviceBox];
    self.devCountLabel = [UILabel new];
    self.devCountLabel.text = @"--";
    self.devCountLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];
    self.devCountLabel.textColor = [UIColor BB_NEON_BLUE];
    self.devCountLabel.textAlignment = NSTextAlignmentCenter;
    self.devCountLabel.frame = CGRectMake(12, 8, w - 24, 34);
    [self.deviceBox addSubview:self.devCountLabel];
    UILabel *devSub = [UILabel new];
    devSub.text = @"当前在线设备";
    devSub.font = [UIFont systemFontOfSize:12];
    devSub.textColor = [UIColor BB_DARK_GRAY];
    devSub.textAlignment = NSTextAlignmentCenter;
    devSub.frame = CGRectMake(12, 46, w - 24, 18);
    [self.deviceBox addSubview:devSub];
    // 智能命名按钮（设备数量卡下方）
    UIButton *smartNameBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    smartNameBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [smartNameBtn setTitle:@"🔤 智能命名" forState:UIControlStateNormal];
    [smartNameBtn setTitleColor:[UIColor BB_NEON_BLUE] forState:UIControlStateNormal];
    smartNameBtn.layer.cornerRadius = 8;
    smartNameBtn.layer.borderWidth = 1;
    smartNameBtn.layer.borderColor = [UIColor BB_NEON_BLUE].CGColor;
    smartNameBtn.frame = CGRectMake(16, y + 86, w, 36);
    [smartNameBtn addTarget:self action:@selector(smartNameTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.scrollView addSubview:smartNameBtn];
    self.deviceRows = [NSMutableArray array];
    y += 78 + 16 + 44;

    // 操作反馈
    self.statusLabel = [UILabel new];
    self.statusLabel.frame = CGRectMake(16, y, w, 20);
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = UIColor.BB_DARK_GRAY;
    self.statusLabel.text = @"";
    [self.scrollView addSubview:self.statusLabel];
    y += 26;

    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y);

    [self startRefreshTimers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startRefreshTimers];
    [self refreshNow];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [self stopRefreshTimers];
}

// ── 采集 ──
- (void)refreshNow {
    if (self.refreshing) return;
    self.refreshing = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *host = @"6.6.6.1";
        int port = 22;
        NSString *user = @"root";
        NSString *pass = @"1124716760...";
        // 实时网速：读当前计数器（App 端算差值，不阻塞）
        NSString *cmd = @"R1=$(awk '/pppoe-wan/{print $2}' /proc/net/dev); T1=$(awk '/pppoe-wan/{print $10}' /proc/net/dev); echo \"SPEED:$R1|$T1\"\n"
                        @"T=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); echo \"TEMP:$T\"\n"
                        @"U=$(uptime); echo \"UPTIME:$U\"\n"
                        @"M=$(free -k | grep Mem); echo \"MEM:$M\"\n"
                        @"D=$(df -h /overlay 2>/dev/null | tail -1); echo \"DISK:$D\"\n"
                        @"C=$(top -n 1 2>/dev/null | grep ^CPU:); echo \"CPU:$C\"\n"
                        @"V=$(cat /root/traffic_month.txt 2>/dev/null); echo \"VN:$V\"\n"
                        @"IP=$(curl -4 -s -m 5 ifconfig.me 2>/dev/null || curl -4 -s -m 5 api.ipify.org 2>/dev/null || curl -4 -s -m 5 ip.sb 2>/dev/null); echo \"PUBIP:$IP\"\n"
                        @"echo \"IPHIST:\"; tail -5 /root/ip_history.txt 2>/dev/null";
        NSString *err = nil;
        NSString *out = WrtSSHExec(host, port, user, pass, cmd, NO, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.refreshing = NO;
            if (out) {
                NSTimeInterval nowT = [NSDate date].timeIntervalSince1970;
                if (weakSelf.lastUpdateTime > 0) {
                    long ago = (long)(nowT - weakSelf.lastUpdateTime);
                    weakSelf.upCard.rightLabel.text = [NSString stringWithFormat:@"%ld秒前更新", ago];
                } else {
                    weakSelf.upCard.rightLabel.text = @"刚刚更新";
                }
                weakSelf.lastUpdateTime = nowT;
                [weakSelf updateStatusDot:YES];
                [weakSelf parseAndRender:out];
                weakSelf.upCard.rightLabel.textColor = [UIColor BB_NEON_GREEN];
            } else {
                [weakSelf updateStatusDot:NO];
                weakSelf.upCard.rightLabel.text = @"连接已断开";
                weakSelf.upCard.rightLabel.textColor = [UIColor BB_NEON_RED];
            }
        });
    });
}

- (void)parseAndRender:(NSString *)raw {
    CGFloat w = self.view.bounds.size.width - 32;
    NSArray *lines = [raw componentsSeparatedByString:@"\n"];
    NSString *tempLine = nil, *upLine = nil, *memLine = nil, *diskLine = nil, *loadLine = nil, *vnJson = nil, *pubIp = nil, *cpuLine = nil, *ipHist = nil, *speedLine = nil;
    for (NSString *ln in lines) {
        if ([ln hasPrefix:@"SPEED:"]) speedLine = [ln substringFromIndex:6];
        else if ([ln hasPrefix:@"TEMP:"]) tempLine = [ln substringFromIndex:5];
        else if ([ln hasPrefix:@"UPTIME:"]) upLine = [ln substringFromIndex:7];
        else if ([ln hasPrefix:@"MEM:"]) memLine = [ln substringFromIndex:4];
        else if ([ln hasPrefix:@"DISK:"]) diskLine = [ln substringFromIndex:5];
        else if ([ln hasPrefix:@"LOAD:"]) loadLine = [ln substringFromIndex:5];
        else if ([ln hasPrefix:@"CPU:"]) cpuLine = [ln substringFromIndex:4];
        else if ([ln hasPrefix:@"VN:"]) vnJson = [ln substringFromIndex:3];
        else if ([ln hasPrefix:@"PUBIP:"]) pubIp = [ln substringFromIndex:6];
        else if ([ln hasPrefix:@"IPHIST:"]) ipHist = [ln substringFromIndex:7];
    }

    // 实时网速仪表盘（App 端算差值：本次计数器 - 上次 / 时间间隔）
    if (speedLine && [speedLine containsString:@"|"]) {
        NSArray *sp = [speedLine componentsSeparatedByString:@"|"];
        if (sp.count >= 2) {
            unsigned long long rxNow = [sp[0] longLongValue];
            unsigned long long txNow = [sp[1] longLongValue];
            NSTimeInterval nowT = [NSDate date].timeIntervalSince1970;
            if (self.lastCounterTime > 0 && nowT > self.lastCounterTime) {
                double dt = nowT - self.lastCounterTime;
                double dl = rxNow > self.lastRxCounter ? (double)(rxNow - self.lastRxCounter) / dt : 0;
                double ul = txNow > self.lastTxCounter ? (double)(txNow - self.lastTxCounter) / dt : 0;
                [self.speedGauge setSpeedDl:dl ul:ul];
            }
            self.lastRxCounter = rxNow;
            self.lastTxCounter = txNow;
            self.lastCounterTime = nowT;
        }
    }

    // 温度（毫度 → 度）
    NSNumber *temp = nil;
    if (tempLine.length > 0) {
        int mv = [tempLine intValue];
        temp = @(mv / 1000.0);
    }
    self.tempCard.valueLabel.text = temp ? [NSString stringWithFormat:@"%.0f°C", temp.doubleValue] : @"--";
    self.tempCard.valueLabel.textColor = [self tempColor:temp];
    self.tempCard.subLabel.text = @"MT7986 处理器";

    // CPU 使用率（从 top 的 idle% 计算，更直观；load average 作副标题）
    if (cpuLine && [cpuLine containsString:@"idle"]) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)% idle" options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:cpuLine options:0 range:NSMakeRange(0, cpuLine.length)];
        if (m) {
            double idle = [[cpuLine substringWithRange:[m rangeAtIndex:1]] doubleValue];
            double usage = 100.0 - idle;
            self.loadCard.valueLabel.text = [NSString stringWithFormat:@"%.0f%%", usage];
            self.loadCard.subLabel.text = @"CPU 使用率";
        } else {
            self.loadCard.valueLabel.text = @"--";
        }
    } else {
        self.loadCard.valueLabel.text = @"--";
    }

    // 运行时间
    int secs = 0;
    if (upLine) {
        NSString *body = upLine;
        // 先去掉 load average 部分
        NSRange loadR = [body rangeOfString:@" load average"];
        if (loadR.location != NSNotFound) body = [body substringToIndex:loadR.location];
        // 去掉 " up " 前缀
        NSRange upR = [body rangeOfString:@" up "];
        if (upR.location != NSNotFound) body = [body substringFromIndex:upR.location + 4];
        body = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        // body 形如: "3 days, 19:56" / "19:56" / "3 days" / "10 min"
        NSRegularExpression *reDay = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\s+day" options:0 error:nil];
        NSRegularExpression *reHM = [NSRegularExpression regularExpressionWithPattern:@"(\\d+):(\\d+)" options:0 error:nil];
        NSRegularExpression *reMin = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\s+min" options:0 error:nil];
        NSTextCheckingResult *dm = [reDay firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        NSTextCheckingResult *hm = [reHM firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        NSTextCheckingResult *mm = [reMin firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        if (dm) secs += [[body substringWithRange:[dm rangeAtIndex:1]] intValue] * 86400;
        if (hm) secs += [[body substringWithRange:[hm rangeAtIndex:1]] intValue] * 3600
                      + [[body substringWithRange:[hm rangeAtIndex:2]] intValue] * 60;
        else if (mm) secs += [[body substringWithRange:[mm rangeAtIndex:1]] intValue] * 60;
    }
    self.upCard.valueLabel.text = secs > 0 ? [NSString stringWithFormat:@"%d天 %d时 %d分", secs/86400, (secs%86400)/3600, (secs%3600)/60] : @"--";
    self.upCard.subLabel.text = secs > 0 ? @"自上次重启以来" : @"";

    // 内存（busybox free -k，单位 KB；使用 (total-available)/total 口径，与主流监控一致）
    NSArray *mems = [memLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *memClean = [mems filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    // Mem: total used free shared buff/cache available
    if (memClean.count >= 7) {
        double totalKB = [memClean[1] doubleValue];
        double usedKB = [memClean[2] doubleValue];
        double availKB = [memClean[6] doubleValue];
        if (totalKB > 0) {
            double usedCalc = totalKB - availKB;
            if (usedCalc < 0) usedCalc = 0;
            double totalMB = totalKB / 1024.0;
            double usedMB = usedCalc / 1024.0;
            self.memCard.valueLabel.text = [NSString stringWithFormat:@"已用 %.0f MB / 共 %.0f MB", usedMB, totalMB];
            [self.memCard setPct:usedCalc / totalKB * 100.0];
        }
    } else if (memClean.count >= 3) {
        double totalKB = [memClean[1] doubleValue];
        double usedKB = [memClean[2] doubleValue];
        if (totalKB > 0) {
            double totalMB = totalKB / 1024.0;
            double usedMB = usedKB / 1024.0;
            self.memCard.valueLabel.text = [NSString stringWithFormat:@"已用 %.0f MB / 共 %.0f MB", usedMB, totalMB];
            [self.memCard setPct:usedKB / totalKB * 100.0];
        }
    } else {
        self.memCard.valueLabel.text = @"--";
    }

    // 硬盘
    NSArray *disks = [diskLine componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSArray *diskClean = [disks filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    if (diskClean.count >= 5) {
        NSString *totalS = diskClean[1];
        NSString *usedS = diskClean[2];
        double pct = [[diskClean[4] stringByReplacingOccurrencesOfString:@"%" withString:@""] doubleValue];
        self.diskCard.valueLabel.text = [NSString stringWithFormat:@"已用 %@ / 总 %@", usedS, totalS];
        [self.diskCard setPct:pct];
    } else {
        self.diskCard.valueLabel.text = @"--";
    }

    // 外网流量（内核计数器累计: rx|tx|月份，绝对准确）
    if (vnJson && [vnJson containsString:@"|"]) {
        NSArray *tp = [vnJson componentsSeparatedByString:@"|"];
        if (tp.count >= 3) {
            double rxB = [tp[0] doubleValue];
            double txB = [tp[1] doubleValue];
            NSString *monthStr = tp[2];
            if (rxB > 0 || txB > 0) {
                self.trafficVal.text = [NSString stringWithFormat:@"↓ 下载 %@   ↑ 上传 %@",
                    [self formatBytes:rxB], [self formatBytes:txB]];
                self.trafficSub.text = [NSString stringWithFormat:@"%@ 月累计（外网口）", monthStr];
            } else {
                self.trafficVal.text = @"--";
                self.trafficSub.text = @"统计中…";
            }
        } else {
            self.trafficVal.text = @"--";
            self.trafficSub.text = @"暂无数据";
        }
    } else {
        self.trafficVal.text = @"--";
        self.trafficSub.text = @"暂无数据";
    }

    // 公网 IP 记录（从路由器历史文件读当前+上次）
    if (pubIp && pubIp.length > 3) {
        self.ipVal.text = pubIp;
        // 解析历史文件：每行 "时间戳|IP"
        NSArray *histLines = [ipHist componentsSeparatedByString:@"\n"];
        NSString *prevIp = nil;
        NSTimeInterval prevTs = 0;
        NSTimeInterval firstTs = 0;   // 最早一条记录（用于判断 IP 未变更时长）
        for (int i = (int)histLines.count - 1; i >= 0; i--) {
            NSString *ln = [histLines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (ln.length == 0) continue;
            NSArray *parts = [ln componentsSeparatedByString:@"|"];
            if (parts.count == 2) {
                double ts = [parts[0] doubleValue];
                NSString *ip = parts[1];
                if (firstTs == 0) firstTs = ts;
                if (![ip isEqualToString:pubIp] && prevIp == nil) {
                    prevIp = ip;
                    prevTs = ts;
                }
            }
        }
        NSString *agoStr = @"";
        NSTimeInterval refTs = prevTs > 0 ? prevTs : firstTs;
        if (refTs > 0) {
            NSTimeInterval diff = [[NSDate date] timeIntervalSince1970] - refTs;
            if (diff < 0) diff = 0;
            int days = (int)(diff / 86400);
            int hours = (int)((int)diff % 86400) / 3600;
            int mins = (int)((int)diff % 3600) / 60;
            if (days > 0) agoStr = [NSString stringWithFormat:@"%d 天 %d 小时前", days, hours];
            else if (hours > 0) agoStr = [NSString stringWithFormat:@"%d 小时 %d 分钟前", hours, mins];
            else agoStr = [NSString stringWithFormat:@"%d 分钟前", MAX(mins, 1)];
        }
        if (prevIp && prevTs > 0) {
            self.ipSub.text = [NSString stringWithFormat:@"上次 %@ · %@变更", prevIp, agoStr];
        } else if (firstTs > 0) {
            self.ipSub.text = [NSString stringWithFormat:@"IP 未变更 · 已保持 %@", agoStr];
        } else {
            self.ipSub.text = @"暂无历史记录";
        }
    } else {
        self.ipVal.text = @"--";
        self.ipSub.text = @"获取失败";
    }

    // 设备列表：每次刷新周期更新一次（3秒），新设备能及时出现
    [self fetchDevices];
}

- (double)unitMultiplier:(NSString *)unit {
    if ([unit hasPrefix:@"KiB"] || [unit hasPrefix:@"KB"]) return 1024.0;
    if ([unit hasPrefix:@"MiB"] || [unit hasPrefix:@"MB"]) return 1024.0 * 1024.0;
    if ([unit hasPrefix:@"GiB"] || [unit hasPrefix:@"GB"]) return 1024.0 * 1024.0 * 1024.0;
    if ([unit hasPrefix:@"TiB"] || [unit hasPrefix:@"TB"]) return 1024.0 * 1024.0 * 1024.0 * 1024.0;
    return 1.0;
}

- (NSString *)formatBytes:(double)b {
    if (b >= 1024.0*1024.0*1024.0) return [NSString stringWithFormat:@"%.2f GB", b/1024.0/1024.0/1024.0];
    if (b >= 1024.0*1024.0) return [NSString stringWithFormat:@"%.1f MB", b/1024.0/1024.0];
    if (b >= 1024.0) return [NSString stringWithFormat:@"%.0f KB", b/1024.0];
    return [NSString stringWithFormat:@"%.0f B", b];
}

// ── 服务状态 ──
// ── 设备列表 ──
- (void)fetchDevices {
    static BOOL fetchingDev = NO;
    if (fetchingDev) return;
    fetchingDev = YES;
    NSString *err = nil;
    // 只拉 DHCP 租约（设备流量统计因 PassWall 代理无法准确归因，已移除）
    NSString *cmd = @"cat /tmp/dhcp.leases 2>/dev/null";
    NSString *out = WrtSSHExec(@"6.6.6.1", 22, @"root", @"1124716760...", cmd, NO, &err);
    dispatch_async(dispatch_get_main_queue(), ^{
        fetchingDev = NO;
        if (out) {
            NSArray *lines = [out componentsSeparatedByString:@"\n"];
            NSMutableArray *devs = [NSMutableArray array];
            for (NSString *ln in lines) {
                NSArray *p = [ln componentsSeparatedByString:@" "];
                if (p.count >= 4 && [p[2] length] > 0) {
                    [devs addObject:[NSMutableDictionary dictionaryWithDictionary:@{
                        @"ip": p[2], @"mac": p[1], @"name": p[3]}]];
                }
            }
            // 设备变化通知（工具箱开关开启时）
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"v_dev_notify"]) {
                [self checkDeviceChanges:devs];
            }
            [self renderDevices:devs];
        }
    });
}

// 设备上线/下线检测：弹横幅 + 声音提醒
- (void)checkDeviceChanges:(NSArray *)nowDevs {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *oldMacs = [ud arrayForKey:@"v_dev_macs"];
    NSMutableArray *nowMacs = [NSMutableArray array];
    NSMutableDictionary *nameByMac = [NSMutableDictionary dictionary];
    for (NSDictionary *d in nowDevs) {
        [nowMacs addObject:d[@"mac"]];
        nameByMac[d[@"mac"]] = d[@"name"];
    }
    if (oldMacs && oldMacs.count > 0) {
        // 新增设备
        for (NSString *mac in nowMacs) {
            if (![oldMacs containsObject:mac]) {
                NSString *nm = nameByMac[mac] ?: @"设备";
                if ([nm isEqualToString:@"*"]) nm = @"新设备";
                [self showDeviceBanner:[NSString stringWithFormat:@"📱 %@ 已连接", nm] detail:[NSString stringWithFormat:@"%@", [self ipForMac:mac inDevs:nowDevs]]];
                PlayConfirmSound();
            }
        }
        // 下线设备
        for (NSString *mac in oldMacs) {
            if (![nowMacs containsObject:mac]) {
                NSString *nm = nameByMac[mac] ?: @"设备";
                if ([nm isEqualToString:@"*"]) nm = @"设备";
                [self showDeviceBanner:[NSString stringWithFormat:@"⚪ %@ 已断开", nm] detail:@""];
            }
        }
    }
    [ud setObject:nowMacs forKey:@"v_dev_macs"];
    [ud synchronize];
}

- (NSString *)ipForMac:(NSString *)mac inDevs:(NSArray *)devs {
    for (NSDictionary *d in devs) {
        if ([d[@"mac"] isEqualToString:mac]) return d[@"ip"];
    }
    return @"";
}

// 设备横幅（顶部弹窗）
- (void)showDeviceBanner:(NSString *)title detail:(NSString *)detail {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
            message:detail preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)renderDevices:(NSArray *)devs {
    // 只显示设备数量，不渲染详细列表
    self.lastDevices = devs;
    self.devCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)devs.count];
}



// ── 智能命名：识别设备厂商并显示 ──
- (void)smartNameTapped {
    HapticTap();
    self.statusLabel.text = @"扫描设备中…";
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        NSString *out = WrtSSHExec(@"6.6.6.1", 22, @"root", @"1124716760...",
            @"cat /tmp/dhcp.leases 2>/dev/null | awk '{print $2\"|\"$3\"|\"$4}'", NO, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!out) {
                weakSelf.statusLabel.text = @"扫描失败";
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                return;
            }
            // 解析设备，按 MAC 前缀识别厂商
            NSMutableString *result = [NSMutableString string];
            NSArray *lines = [out componentsSeparatedByString:@"\n"];
            for (NSString *ln in lines) {
                NSArray *p = [ln componentsSeparatedByString:@"|"];
                if (p.count >= 3) {
                    NSString *mac = p[0];
                    NSString *ip = p[1];
                    NSString *name = [p[2] isEqualToString:@"*"] ? @"(未命名)" : p[2];
                    NSString *vendor = [weakSelf vendorFromMac:mac];
                    [result appendFormat:@"%@ | %@ | %@\n", name, ip, vendor];
                }
            }
            if (result.length == 0) [result appendString:@"暂无设备"];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔤 设备识别"
                message:result preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
            weakSelf.statusLabel.text = @"扫描完成";
            weakSelf.statusLabel.textColor = UIColor.systemGreenColor;
        });
    });
}

- (NSString *)vendorFromMac:(NSString *)mac {
    // 常见厂商 OUI 前缀识别
    NSString *prefix = [mac substringToIndex:8].uppercaseString;  // 形如 00:0C:29
    NSDictionary *vendors = @{
        @"00:0C:29": @"VMware", @"00:50:56": @"VMware", @"00:05:69": @"VMware",
        @"30:95:87": @"小米", @"B4:60:ED": @"小米", @"54:48:E6": @"小米",
        @"58:B6:23": @"小米", @"94:F8:27": @"小米", @"C8:5C:CC": @"小米",
        @"A8:40:7D": @"Apple", @"44:DF:65": @"TP-Link", @"7C:83:34": @"Intel",
        @"00:0C:29": @"VMware"
    };
    NSString *v = vendors[prefix];
    return v ?: @"未知设备";
}

- (void)confirmRebootWrt {
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"重启路由器";
    vc.confirmMessage = @"重启 OpenWrt 路由器？\n⚠️ 所有设备将断网约 1-2 分钟！";
    vc.slideText = @"滑动重启";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf doRebootWrt]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)doRebootWrt {
    HapticTap();
    self.statusLabel.text = @"重启路由器中…";
    [self addLog:@"重启路由器中…"];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        WrtSSHExec(@"6.6.6.1", 22, @"root", @"1124716760...", @"reboot", YES, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.statusLabel.text = @"✅ 重启指令已发送，约 1-2 分钟后恢复";
            [weakSelf addLog:@"✅ 重启指令已发送"];
            PlayConfirmSound();
        });
    });
}

- (void)startRefreshTimers {
    if (!self.refreshTimer) {
        self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self
                                                           selector:@selector(refreshNow)
                                                           userInfo:nil repeats:YES];
    }
}

- (void)stopRefreshTimers {
    [self.refreshTimer invalidate];
    self.refreshTimer = nil;
}

- (void)applicationDidBecomeActive {
    [self startRefreshTimers];
    [self refreshNow];
    if (self.keepAlivePlayer && !self.keepAlivePlayer.isPlaying) [self.keepAlivePlayer play];
}

- (void)applicationDidEnterBackground {
    [self stopRefreshTimers];
}
@end

// ══════════════════════════════════════════════════════════════
// 工具箱页（网络体检 / 压力测试 / 设备通知设置）
// ══════════════════════════════════════════════════════════════
@interface ToolboxVC : UIViewController
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *healthResultBox;   // 体检结果区
@property (nonatomic, strong) UILabel *healthResultLabel;
@property (nonatomic, strong) UILabel *healthProgress;   // 体检进度文字
@property (nonatomic, strong) UIProgressView *healthBar;  // 体检进度条
@property (nonatomic, strong) NSTimer *healthTimer;      // 体检进度定时器
@property (nonatomic) NSInteger healthElapsed;
@property (nonatomic, strong) UIView *speedBox;            // 测速结果区
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *speedProgress;       // 实时进度
@property (nonatomic, strong) UIProgressView *speedBar;           // 进度条
@property (nonatomic, strong) NSTimer *speedTimer;                // 进度定时器
@property (nonatomic) NSInteger speedElapsed;                     // 已用秒数
@property (nonatomic) BOOL running;
@end

@implementation ToolboxVC

- (UILabel *)sectionLabelWithTitle:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    l.textColor = [UIColor colorWithRed:0.20 green:0.23 blue:0.29 alpha:1];
    [self.scrollView addSubview:l];
    return l;
}

- (UIView *)makeCard:(CGRect)frame {
    GlassCard *c = [[GlassCard alloc] initWithFrame:frame];
    [self.scrollView addSubview:c];
    return c;
}

- (UIButton *)makeBtn:(NSString *)title color:(UIColor *)color frame:(CGRect)frame action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:color forState:UIControlStateNormal];
    b.layer.cornerRadius = 10;
    b.layer.borderWidth = 1;
    b.layer.borderColor = color.CGColor;
    b.frame = frame;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor BB_BG_COLOR;
    self.title = @"工具箱";

    self.scrollView = [UIScrollView new];
    self.scrollView.backgroundColor = [UIColor clearColor];
    self.scrollView.frame = self.view.bounds;
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];

    CGFloat w = self.view.bounds.size.width - 32;
    CGFloat y = 16;

    // ── 网络体检 ──
    UILabel *s1 = [self sectionLabelWithTitle:@"🔍 网络体检"];
    s1.frame = CGRectMake(16, y, w, 20); y += 26;
    UIView *card1 = [self makeCard:CGRectMake(16, y, w, 120)];
    UILabel *d1 = [UILabel new];
    d1.text = @"检测外网连通、DNS、丢包、延迟、网速";
    d1.font = [UIFont systemFontOfSize:12];
    d1.textColor = UIColor.BB_DARK_GRAY;
    d1.frame = CGRectMake(14, 10, w - 28, 18);
    [card1 addSubview:d1];
    UIButton *b1 = [self makeBtn:@"开始体检" color:[UIColor BB_NEON_BLUE]
        frame:CGRectMake(14, 38, w - 28, 40) action:@selector(confirmHealthCheck)];
    [card1 addSubview:b1];
    self.healthResultBox = [[GlassCard alloc] initWithFrame:CGRectMake(16, y + 88, w, 0)];
    self.healthResultBox.hidden = YES;
    [self.scrollView addSubview:self.healthResultBox];
    self.healthResultLabel = [UILabel new];
    self.healthResultLabel.font = [UIFont systemFontOfSize:12];
    self.healthResultLabel.textColor = UIColor.BB_WHITE_TEXT;
    self.healthResultLabel.numberOfLines = 0;
    [self.healthResultBox addSubview:self.healthResultLabel];
    // 体检进度条（卡片内）
    self.healthProgress = [UILabel new];
    self.healthProgress.text = @"";
    self.healthProgress.font = [UIFont systemFontOfSize:12];
    self.healthProgress.textColor = UIColor.BB_DARK_GRAY;
    self.healthProgress.textAlignment = NSTextAlignmentCenter;
    self.healthProgress.frame = CGRectMake(14, 78, w - 28, 18);
    [card1 addSubview:self.healthProgress];
    self.healthBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.healthBar.frame = CGRectMake(14, 98, w - 28, 4);
    self.healthBar.progressTintColor = [UIColor BB_NEON_BLUE];
    self.healthBar.trackTintColor = [UIColor colorWithRed:0.92 green:0.94 blue:0.96 alpha:1];
    self.healthBar.progress = 0;
    [card1 addSubview:self.healthBar];
    y += 120 + 16;

    // ── 宽带测速 ──
    UILabel *sSpeed = [self sectionLabelWithTitle:@"🚀 宽带测速"];
    sSpeed.frame = CGRectMake(16, y, w, 20); y += 26;
    UIView *speedCard = [self makeCard:CGRectMake(16, y, w, 120)];
    UILabel *dSpeed = [UILabel new];
    dSpeed.text = @"一键测试宽带下载/上传速率（约 20 秒）";
    dSpeed.font = [UIFont systemFontOfSize:12];
    dSpeed.textColor = UIColor.BB_DARK_GRAY;
    dSpeed.frame = CGRectMake(14, 10, w - 28, 18);
    [speedCard addSubview:dSpeed];
    UIButton *bSpeed = [self makeBtn:@"开始测速" color:[UIColor systemPurpleColor]
        frame:CGRectMake(14, 38, w - 28, 40) action:@selector(confirmSpeedTest)];
    [speedCard addSubview:bSpeed];
    self.speedProgress = [UILabel new];
    self.speedProgress.text = @"";
    self.speedProgress.font = [UIFont systemFontOfSize:12];
    self.speedProgress.textColor = UIColor.BB_DARK_GRAY;
    self.speedProgress.textAlignment = NSTextAlignmentCenter;
    self.speedProgress.frame = CGRectMake(14, 78, w - 28, 18);
    [speedCard addSubview:self.speedProgress];
    self.speedBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleBar];
    self.speedBar.frame = CGRectMake(14, 98, w - 28, 4);
    self.speedBar.progressTintColor = [UIColor systemPurpleColor];
    self.speedBar.trackTintColor = [UIColor colorWithRed:0.92 green:0.94 blue:0.96 alpha:1];
    self.speedBar.progress = 0;
    [speedCard addSubview:self.speedBar];
    self.speedBox = [[GlassCard alloc] initWithFrame:CGRectMake(16, y + 100, w, 0)];
    self.speedBox.hidden = YES;
    [self.scrollView addSubview:self.speedBox];
    self.speedLabel = [UILabel new];
    self.speedLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.speedLabel.textColor = UIColor.BB_WHITE_TEXT;
    self.speedLabel.numberOfLines = 0;
    [self.speedBox addSubview:self.speedLabel];
    y += 120 + 16;

    // ── 设备通知设置 ──
    UILabel *s3 = [self sectionLabelWithTitle:@"📱 设备通知"];
    s3.frame = CGRectMake(16, y, w, 20); y += 26;
    UIView *card3 = [self makeCard:CGRectMake(16, y, w, 96)];
    UILabel *d3 = [UILabel new];
    d3.text = @"所有设备连接/断开时横幅+声音提醒";
    d3.font = [UIFont systemFontOfSize:12];
    d3.textColor = UIColor.BB_DARK_GRAY;
    d3.frame = CGRectMake(14, 12, w - 100, 18);
    [card3 addSubview:d3];
    UISwitch *sw = [UISwitch new];
    sw.transform = CGAffineTransformMakeScale(0.8, 0.8);
    sw.frame = CGRectMake(w - 70, 30, 51, 32);
    sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"v_dev_notify"];
    [sw addTarget:self action:@selector(notifySwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [card3 addSubview:sw];
    UILabel *note3 = [UILabel new];
    note3.text = @"需保持 App 前台运行才能接收";
    note3.font = [UIFont systemFontOfSize:10];
    note3.textColor = UIColor.BB_DARK_GRAY;
    note3.frame = CGRectMake(14, 60, w - 28, 14);
    [card3 addSubview:note3];
    y += 96 + 16;

    // 状态
    self.statusLabel = [UILabel new];
    self.statusLabel.frame = CGRectMake(16, y, w, 20);
    self.statusLabel.font = [UIFont systemFontOfSize:13];
    self.statusLabel.textColor = UIColor.BB_DARK_GRAY;
    self.statusLabel.text = @"";
    [self.scrollView addSubview:self.statusLabel];
    y += 30;

    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y);
}

// 通知开关（二次确认）
- (void)notifySwitchChanged:(UISwitch *)sw {
    BOOL toOn = sw.isOn;
    __weak typeof(self) weakSelf = self;
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = toOn ? @"开启设备通知" : @"关闭设备通知";
    vc.confirmMessage = toOn ? @"开启所有设备连接/断开提醒？" : @"关闭设备连接/断开提醒？";
    vc.slideText = toOn ? @"滑动开启" : @"滑动关闭";
    vc.onConfirm = ^{
        [[NSUserDefaults standardUserDefaults] setBool:toOn forKey:@"v_dev_notify"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        HapticTap();
        weakSelf.statusLabel.text = toOn ? @"✅ 设备通知已开启" : @"设备通知已关闭";
        weakSelf.statusLabel.textColor = toOn ? [UIColor systemGreenColor] : UIColor.BB_DARK_GRAY;
    };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sw.on = !toOn;
    });
}

// ── 网络体检 ──
- (void)confirmHealthCheck {
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"网络体检";
    vc.confirmMessage = @"开始检测外网连通、DNS、丢包、延迟、网速？\n约需 15-30 秒。";
    vc.slideText = @"滑动开始";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf startHealthCheck]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)startHealthCheck {
    if (self.running) return;
    self.running = YES;
    self.statusLabel.text = @"体检中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    self.healthProgress.text = @"准备中…（剩余 25 秒）";
    self.healthBar.progress = 0;
    self.healthElapsed = 0;
    HapticTap();
    __weak typeof(self) weakSelf = self;
    self.healthTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
        selector:@selector(healthTick) userInfo:nil repeats:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        NSString *out = WrtSSHExec(@"6.6.6.1", 22, @"root", @"1124716760...", @"/root/healthcheck.sh 2>/dev/null", NO, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.healthTimer invalidate];
            weakSelf.healthTimer = nil;
            weakSelf.running = NO;
            weakSelf.healthBar.progress = 1.0;
            if (!out) {
                weakSelf.statusLabel.text = @"体检失败：无法连接路由器";
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                weakSelf.healthProgress.text = @"";
                return;
            }
            [weakSelf renderHealth:out];
        });
    });
}

- (void)healthTick {
    self.healthElapsed++;
    NSInteger remain = MAX(25 - (NSInteger)self.healthElapsed, 0);
    self.healthBar.progress = MIN((float)self.healthElapsed / 25.0, 1.0);
    if (remain > 0) {
        self.healthProgress.text = [NSString stringWithFormat:@"体检中…（剩余 %ld 秒）", (long)remain];
    } else {
        self.healthProgress.text = @"体检中…（即将完成）";
    }
}

- (void)renderHealth:(NSString *)raw {
    NSMutableString *result = [NSMutableString string];
    NSString *httpRes = @"--", *dnsRes = @"--", *pingRes = @"--", *speedRes = @"--";
    NSArray *parts = [raw componentsSeparatedByString:@"\n"];
    BOOL inHTTP = NO, inDNS = NO, inPING = NO, inSPEED = NO;
    for (NSString *ln in parts) {
        if ([ln hasPrefix:@"==HTTP=="]) { inHTTP = YES; inDNS = inPING = inSPEED = NO; continue; }
        if ([ln hasPrefix:@"==DNS=="]) { inDNS = YES; inHTTP = inPING = inSPEED = NO; continue; }
        if ([ln hasPrefix:@"==PING=="]) { inPING = YES; inHTTP = inDNS = inSPEED = NO; continue; }
        if ([ln hasPrefix:@"==SPEED=="]) { inSPEED = YES; inHTTP = inDNS = inPING = NO; continue; }
        if (inHTTP && ln.length > 0) httpRes = ln;
        else if (inDNS && ln.length > 0) dnsRes = ln;
        else if (inPING && ln.length > 0) pingRes = ln;
        else if (inSPEED && ln.length > 0) {
            double spd = [ln doubleValue];
            speedRes = [NSString stringWithFormat:@"%@/s", [self fmtSpeed:spd]];
        }
    }
    [result appendFormat:@"✅ 外网连通：%@\n✅ DNS 解析：%@\n✅ 丢包/延迟：%@\n🚀 测速：%@",
        httpRes, dnsRes, pingRes, speedRes];
    self.healthResultLabel.text = result;
    self.healthResultLabel.frame = CGRectMake(12, 10, self.view.bounds.size.width - 56, 90);
    self.healthResultBox.frame = CGRectMake(16, self.healthResultBox.frame.origin.y, self.view.bounds.size.width - 32, 110);
    self.healthResultBox.hidden = NO;
    self.statusLabel.text = @"体检完成";
    self.statusLabel.textColor = [UIColor BB_NEON_GREEN];
    self.healthProgress.text = @"";
    PlayConfirmSound();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔍 体检完成"
        message:result preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    [self layoutResults];
}

- (NSString *)fmtSpeed:(double)bytesPerSec {
    if (bytesPerSec >= 1048576) return [NSString stringWithFormat:@"%.2f MB", bytesPerSec / 1048576];
    if (bytesPerSec >= 1024) return [NSString stringWithFormat:@"%.0f KB", bytesPerSec / 1024];
    return [NSString stringWithFormat:@"%.0f B", bytesPerSec];
}

// ── 宽带测速 ──
// 测速前滑动确认
- (void)confirmSpeedTest {
    SlideConfirmVC *vc = [SlideConfirmVC new];
    vc.confirmTitle = @"宽带测速";
    vc.confirmMessage = @"开始测试宽带下载/上传速率？\n使用国内节点（腾讯CDN），约需 20 秒。";
    vc.slideText = @"滑动开始";
    __weak typeof(self) weakSelf = self;
    vc.onConfirm = ^{ [weakSelf startSpeedTest]; };
    vc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [self presentViewController:vc animated:NO completion:nil];
}

- (void)startSpeedTest {
    if (self.running) return;
    self.running = YES;
    self.statusLabel.text = @"测速中…";
    self.statusLabel.textColor = UIColor.systemOrangeColor;
    self.speedProgress.text = @"准备中…（剩余 22 秒）";
    self.speedBar.progress = 0;
    self.speedBar.hidden = NO;
    self.speedElapsed = 0;
    HapticTap();
    __weak typeof(self) weakSelf = self;
    // 进度定时器：每秒更新进度条和剩余时间
    self.speedTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
        selector:@selector(speedTick) userInfo:nil repeats:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *err = nil;
        NSString *out = WrtSSHExec(@"6.6.6.1", 22, @"root", @"1124716760...", @"/root/speedtest.sh 2>/dev/null", NO, &err);
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.speedTimer invalidate];
            weakSelf.speedTimer = nil;
            weakSelf.running = NO;
            weakSelf.speedProgress.text = @"";
            weakSelf.speedBar.progress = 1.0;
            if (!out) {
                weakSelf.statusLabel.text = @"测速失败";
                weakSelf.statusLabel.textColor = UIColor.systemRedColor;
                return;
            }
            [weakSelf renderSpeed:out];
        });
    });
}

// 测速进度每秒更新
- (void)speedTick {
    self.speedElapsed++;
    NSInteger remain = MAX(22 - (NSInteger)self.speedElapsed, 0);
    self.speedBar.progress = MIN((float)self.speedElapsed / 22.0, 1.0);
    if (remain > 0) {
        self.speedProgress.text = [NSString stringWithFormat:@"测速中…（剩余 %ld 秒）", (long)remain];
    } else {
        self.speedProgress.text = @"测速中…（即将完成）";
    }
}

- (void)renderSpeed:(NSString *)raw {
    // 解析：==DOWNLOAD== 每行 "秒|Mbps"，==UPLOAD== 同理
    NSMutableArray *dlRates = [NSMutableArray array];
    NSMutableArray *ulRates = [NSMutableArray array];
    BOOL inDL = NO, inUL = NO;
    NSArray *lines = [raw componentsSeparatedByString:@"\n"];
    for (NSString *ln in lines) {
        if ([ln hasPrefix:@"==DOWNLOAD=="]) { inDL = YES; inUL = NO; continue; }
        if ([ln hasPrefix:@"==UPLOAD=="]) { inUL = YES; inDL = NO; continue; }
        NSArray *p = [ln componentsSeparatedByString:@"|"];
        if (p.count >= 2) {
            double rate = [p[1] doubleValue];
            if (inDL) [dlRates addObject:@(rate)];
            else if (inUL) [ulRates addObject:@(rate)];
        }
    }
    double dlMax = 0, ulMax = 0;
    for (NSNumber *n in dlRates) if (n.doubleValue > dlMax) dlMax = n.doubleValue;
    for (NSNumber *n in ulRates) if (n.doubleValue > ulMax) ulMax = n.doubleValue;
    double dlAvg = dlRates.count ? [[dlRates valueForKeyPath:@"@avg.doubleValue"] doubleValue] : 0;
    double ulAvg = ulRates.count ? [[ulRates valueForKeyPath:@"@avg.doubleValue"] doubleValue] : 0;

    self.speedLabel.text = [NSString stringWithFormat:
        @"⬇️ 下载\n  峰值：%.1f Mbps\n  平均：%.1f Mbps\n\n⬆️ 上传\n  峰值：%.1f Mbps\n  平均：%.1f Mbps",
        dlMax, dlAvg, ulMax, ulAvg];
    self.speedLabel.frame = CGRectMake(12, 10, self.view.bounds.size.width - 56, 100);
    self.speedBox.frame = CGRectMake(16, self.speedBox.frame.origin.y, self.view.bounds.size.width - 32, 120);
    self.speedBox.hidden = NO;
    self.statusLabel.text = @"测速完成";
    self.statusLabel.textColor = [UIColor BB_NEON_GREEN];
    PlayConfirmSound();
    [self layoutResults];
}

- (void)layoutResults {
    // 重新计算所有结果框位置：按顺序排列（体检→压测→测速），避免折叠
    CGFloat w = self.view.bounds.size.width - 32;
    CGFloat yAfter = self.statusLabel.frame.origin.y - 26;  // statusLabel 上方开始
    // 结果框统一在各自卡片下方按内容高度排列
    if (!self.healthResultBox.hidden) {
        CGFloat hh = self.healthResultLabel.frame.size.height + 20;
        self.healthResultBox.frame = CGRectMake(16, yAfter, w, hh);
        self.healthResultLabel.frame = CGRectMake(12, 10, w - 24, self.healthResultLabel.frame.size.height);
        yAfter += hh + 10;
    }
    if (!self.speedBox.hidden) {
        CGFloat ph = self.speedLabel.frame.size.height + 20;
        self.speedBox.frame = CGRectMake(16, yAfter, w, ph);
        self.speedLabel.frame = CGRectMake(12, 10, w - 24, self.speedLabel.frame.size.height);
        yAfter += ph + 10;
    }
    // 状态标签和 contentSize 跟随
    self.statusLabel.frame = CGRectMake(16, yAfter, w, 20);
    yAfter += 30;
    self.scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, yAfter);
}

@end

// ══════════════════════════════════════════════════════════════
// App 入口
// ══════════════════════════════════════════════════════════════

// ══════════════════════════════════════════════════════════════
// VApp 嵌入根（原 AppDelegate 组装逻辑 → UITabBarController）
// 由百宝箱 SwiftUI 通过 VAppEmbed 调起
// ══════════════════════════════════════════════════════════════
@interface VAppRootVC : UITabBarController
@property (nonatomic, strong) DashboardVC *dashboard;
@property (nonatomic, strong) OpenWrtVC *openwrtVC;
@property (nonatomic, strong) ToolboxVC *toolboxVC;
@end

@implementation VAppRootVC

- (void)viewDidLoad {
    [super viewDidLoad];
    libssh2_init(0);

    self.dashboard = [DashboardVC new];
    UINavigationController *nav1 = [[UINavigationController alloc] initWithRootViewController:self.dashboard];
    nav1.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"ESXi"
                                                    image:[UIImage systemImageNamed:@"server.rack"]
                                            selectedImage:[UIImage systemImageNamed:@"server.rack.fill"]];

    self.openwrtVC = [OpenWrtVC new];
    UINavigationController *nav2 = [[UINavigationController alloc] initWithRootViewController:self.openwrtVC];
    nav2.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"OpenWrt"
                                                    image:[UIImage systemImageNamed:@"wifi"]
                                            selectedImage:[UIImage systemImageNamed:@"wifi.fill"]];

    self.toolboxVC = [ToolboxVC new];
    UINavigationController *nav3 = [[UINavigationController alloc] initWithRootViewController:self.toolboxVC];
    nav3.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"工具箱"
                                                    image:[UIImage systemImageNamed:@"wrench.and.screwdriver"]
                                            selectedImage:[UIImage systemImageNamed:@"wrench.and.screwdriver.fill"]];

    self.viewControllers = @[nav1, nav2, nav3];
    [self.dashboard setupBackgroundKeepAlive];

    // 并行连接两台设备：触发 viewDidLoad 后立即首刷
    (void)self.dashboard.view;
    (void)self.openwrtVC.view;
    (void)self.toolboxVC.view;
    [self.dashboard refreshNow];
    [self.openwrtVC refreshNow];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appActive)
                                             name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBackground)
                                             name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)appActive { [self.dashboard applicationDidBecomeActive]; }
- (void)appBackground { [self.dashboard applicationDidEnterBackground]; }

@end
