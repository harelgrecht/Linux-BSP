#include "netmonfw.h"
#include "test.h"

/* ============================================================
 *                       GLOBAL VARIABLES
 * ============================================================ */

static LIST_HEAD(gRuleList);              // global rule list
static struct nf_hook_ops gNetMonHookOps; // netfilter operations
static struct proc_dir_entry *gNetMonProcFile; // /proc entry

static const struct proc_ops gNetMonProcOps = {
    .proc_write = netMonProcWrite,
};

/* ============================================================
 *                       HELPER FUNCTIONS
 * ============================================================ */

enum NetMonDirection directionFromString(char direction[DIRECTION_MAX_LEN]) {
    if(strcmp(direction, "source") == 0)
        return FILTER_SOURCE;
    else if(strcmp(direction, "dest") == 0)
        return FILTER_DEST;
    else if(strcmp(direction, "both") == 0)
        return FILTER_BOTH;
    else
        return FILTER_INVALID;
}

static int parsePortValue(const char *value, int *outPort) {
    if (kstrtoint(value, 10, outPort) != 0) {
        pr_warn("netmon: Invalid port number format: %s\n", value);
        return -EINVAL;
    }
    if (*outPort <= 0 || *outPort > 65535) {
        pr_warn("netmon: Port number %d is out of valid range (1-65535)\n", *outPort);
        return -EINVAL;
    }
    return 0;
}

static int ParseIpValue(const char *value, __be32 *outIp) {
    if (in4_pton(value, -1, (uint8_t *)outIp, '\0', NULL) == 0) {
        pr_warn("netmon: Failed to parse invalid IP value: '%s'\n", value);
        return -EINVAL;
    }
    return 0;
}

static int parseMacValue(const char *value, unsigned char outMac[ETH_MAC_LEN]) {
    /*
    the function supports both formats:
    format 1 - 00:1A:2B:3C:4D:5E
    format 1 - 001A2B3C4D5E
    */
    if (sscanf(value, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx", &outMac[0], &outMac[1], &outMac[2], &outMac[3], &outMac[4], &outMac[5]) == ETH_MAC_LEN)        
        return 0;
    if(sscanf(value, "%2hhx%2hhx%2hhx%2hhx%2hhx%2hhx", &outMac[0], &outMac[1], &outMac[2], &outMac[3], &outMac[4], &outMac[5]) == ETH_MAC_LEN)
        return 0;

    return -EINVAL;
}

/* ============================================================
 *                  RULE MANAGEMENT HELPERS
 * ============================================================ */

static bool ruleExist(struct NetMonRule* rule, char searchInterface[IFACE_MAX_LEN], enum NetMonDirection searchDirection, const char *type) {
        if (strcmp(rule->interface, searchInterface) != 0)
        return false;

    if (rule->direction != searchDirection)
        return false;

    if(strcmp(rule->type, type) != 0)
        return false;
    return true;
}

/* Helper function: parse value for removal */
static int parseRemoveRuleValue(const char *type, const char *value, int *portNumber, __be32 *ipAddr, unsigned char* macAddr) {
    if(strcmp(type, RULE_PORT) == 0)
        return parsePortValue(value, portNumber);
    else if(strcmp(type, RULE_IP) == 0)
        return ParseIpValue(value, ipAddr);
    else if(strcmp(type, RULE_MAC) == 0)
        return parseMacValue(value, macAddr);
    return -EINVAL;
}

/* Helper function: check if rule matches for removal */
static bool isMatchingRuleForRemoval(struct NetMonRule *rule, const char *type, int portNumber, __be32 ipAddr, unsigned char macAddr[ETH_MAC_LEN]) {
    if (strcmp(type, RULE_PORT) == 0 && strcmp(rule->type, RULE_PORT) == 0 && rule->portNumber == portNumber) {
        pr_info("netmon: Removing rule for %s (port %d)\n", rule->interface, rule->portNumber);
        return true;
    }
    if (strcmp(type, RULE_IP) == 0 && strcmp(rule->type, RULE_IP) == 0 && rule->ipAddr == ipAddr) {
        pr_info("netmon: Removing rule for %s (ip %pI4)\n", rule->interface, &rule->ipAddr);
        return true;
    }
    if (strcmp(type, RULE_MAC) == 0 && strcmp(rule->type, RULE_MAC) == 0 && memcmp(rule->macAddr, macAddr, ETH_MAC_LEN) == 0) {
        pr_info("netmon: Removing rule for %s (mac %pM)\n", rule->interface, rule->macAddr);
        return true;
    }
    return false;
}


/* Helper function: Fill base data into the rule struct */
static int fillBaseRuleFields(struct NetMonRule* rule, const char* interface, const char* type, const char* direction) {
    rule->direction = directionFromString((char*)direction);
    if (rule->direction == FILTER_INVALID) {
        pr_warn("netmon: Invalid direction specified: %s\n", direction);
        return -EINVAL;
    }

    strlcpy(rule->interface, interface, IFACE_MAX_LEN);
    strlcpy(rule->type, type, TYPE_MAX_LEN);
    return 0;
}

/* ============================================================
 *                     ADD / REMOVE RULES
 * ============================================================ */

static int netMonHandleAddRule(char interface[IFACE_MAX_LEN], char type[TYPE_MAX_LEN], char direction[DIRECTION_MAX_LEN], char value[VALUE_MAX_LEN]) {
    // kzalloc is better then kmalloc cause kzalloc actaully iniat 0 
    struct NetMonRule* tempFilterRule = kzalloc(sizeof(struct NetMonRule), GFP_KERNEL); 
    if(!tempFilterRule) {
        pr_err("netmon: Failed to allocate memory for tempFilterRule\n");
        return -1;
    }

    if (fillBaseRuleFields(tempFilterRule, interface, type, direction) != 0) {
        kfree(tempFilterRule);
        return -EINVAL;
    }

    if(strcmp(type, RULE_PORT) == 0) {
        if(parsePortValue(value, &tempFilterRule->portNumber) != 0) {
            kfree(tempFilterRule);
            return -EINVAL;
        }
        tempFilterRule->ipAddr = 0;
        memset(tempFilterRule->macAddr, 0, ETH_MAC_LEN);

    } else if(strcmp(type, RULE_IP) == 0) {
        if(ParseIpValue(value, &tempFilterRule->ipAddr) != 0) {
            kfree(tempFilterRule);
            return -EINVAL;
        }
        tempFilterRule->portNumber = 0;
        memset(tempFilterRule->macAddr, 0, ETH_MAC_LEN);

    }else if(strcmp(type, RULE_MAC) == 0) {
        if(parseMacValue(value, tempFilterRule->macAddr) != 0) {
            kfree(tempFilterRule);
            return -EINVAL;
        }
        tempFilterRule->portNumber = 0;
        tempFilterRule->ipAddr = 0;
    } else {
        pr_warn("netmon: Unknown filter type: %s\n", type);
        kfree(tempFilterRule);
        return -1;
    }

    list_add_tail(&tempFilterRule->list, &gRuleList);
    pr_info("netmon: Added new rule for %s\n", tempFilterRule->interface);

    return 0;
}

static int netMonHandleRemoveRule(char interface[IFACE_MAX_LEN], char type[TYPE_MAX_LEN], char direction[DIRECTION_MAX_LEN], char value[VALUE_MAX_LEN]) {
    struct NetMonRule* rule;
    struct NetMonRule* temp;
    bool ruleFound = false;
    int portNumber = 0;
    __be32 ipAddress = 0;
    unsigned char macAddr[ETH_MAC_LEN] = {0};
    enum NetMonDirection directionEnum;

    directionEnum = directionFromString(direction); // get direction 
    if(directionEnum == FILTER_INVALID) {
        pr_warn("netmon: Invalid direction specified: %s\n", direction);
        return -EINVAL; 
    }

    if(parseRemoveRuleValue(type, value, &portNumber, &ipAddress, macAddr) != 0) { //parse ip or port from value
        pr_warn("netmon: Invalid value for removal: %s\n", value);
        return -EINVAL;
    }

    list_for_each_entry_safe(rule, temp, &gRuleList, list) {
        if (!ruleExist(rule, interface, directionEnum, type)) // check if rule even exists
            continue;

        if(isMatchingRuleForRemoval(rule, type, portNumber, ipAddress, macAddr)) { 
            list_del(&rule->list);
            kfree(rule);
            ruleFound = true;
            break;
        }
    }
    
    if (!ruleFound) {
        pr_warn("netmon: Rule to remove not found\n");
        return -1;
    }

    return 0;
}

/* ============================================================
 *                     FILTERING HELPERS
 * ============================================================ */

static bool checkIpFilter(struct NetMonRule *rule, __be32 sourceIp, __be32 destIp) {
    if(rule->direction == FILTER_SOURCE) 
        return rule->ipAddr == sourceIp;
    else if(rule->direction == FILTER_DEST) 
        return rule->ipAddr == destIp;
    else if(rule->direction == FILTER_BOTH)
        return ((rule->ipAddr == sourceIp) || (rule->ipAddr == destIp));
        
    return false;
}

static bool checkPortFilter(struct NetMonRule *rule, int sourcePort, int destPort) {
    if(rule->direction == FILTER_SOURCE) 
        return rule->portNumber == sourcePort;
    else if(rule->direction == FILTER_DEST) 
        return rule->portNumber == destPort;
    else if(rule->direction == FILTER_BOTH)
        return ((rule->portNumber == sourcePort) || (rule->portNumber == destPort));

    return false;
}

static bool checkMacFilter(struct NetMonRule *rule, unsigned char sourceMac[ETH_MAC_LEN], unsigned char destMac[ETH_MAC_LEN]) {
    if(rule->direction == FILTER_SOURCE) {
        if(memcmp(rule->macAddr, sourceMac, ETH_MAC_LEN) == 0)
            return true;
    }
    if(rule->direction == FILTER_DEST) {
        if(memcmp(rule->macAddr, destMac, ETH_MAC_LEN) == 0)
            return true;
    }
    if(rule->direction == FILTER_BOTH) {
        if((memcmp(rule->macAddr, sourceMac, ETH_MAC_LEN)) == 0 || (memcmp(rule->macAddr, destMac, ETH_MAC_LEN) == 0))
            return true;
    }

    return false;
}

/* ============================================================
 *                        HOOK FUNCTION
 * ============================================================ */

unsigned int netMonPacketHook(void *priv, struct sk_buff *skb, const struct nf_hook_state *state) {
    struct iphdr *ipHeader;
    struct ethhdr *ethHeader;
    struct tcphdr *tcpHeader;
    struct udphdr *udpHeader;
    size_t ipHeaderLen = 0;
    struct NetMonRule* rule;
    int srcPort = 0, destPort = 0;

    ethHeader = eth_hdr(skb); 
    if(!ethHeader) return NF_ACCEPT;

    ipHeader = ip_hdr(skb); 
    if(!ipHeader) return NF_ACCEPT;

    ipHeaderLen = ipHeader->ihl * WORD_SIZE_BYTE; 

    if(ipHeader->protocol == IPPROTO_TCP) {
        tcpHeader = (struct tcphdr*)((unsigned char*) ipHeader + ipHeaderLen);
        srcPort = ntohs(tcpHeader->source);
        destPort = ntohs(tcpHeader->dest);

    } else if(ipHeader->protocol == IPPROTO_UDP) {
        udpHeader = (struct udphdr*)((unsigned char*) ipHeader + ipHeaderLen);
        srcPort = ntohs(udpHeader->source);
        destPort = ntohs(udpHeader->dest);
    }

    list_for_each_entry(rule, &gRuleList, list) {
        // check if the interface exists
        if(strcmp(state->in->name, rule->interface) != 0) 
            continue;

        if(strcmp(rule->type, RULE_PORT) == 0) {
            if(checkPortFilter(rule, srcPort, destPort)) {
                pr_info("Dropped packet cause by port filter\n");
                return NF_DROP;
            }
            continue;

        } else if(strcmp(rule->type, RULE_IP) == 0) {
            if(checkIpFilter(rule, ipHeader->saddr, ipHeader->daddr)) {
                pr_info("Dropped packet cause by ip filter\n");
                return NF_DROP;
            }
            continue;
        } else if(strcmp(rule->type, RULE_MAC) == 0) {
            if(checkMacFilter(rule, ethHeader->h_source, ethHeader->h_dest)) {
                pr_info("Dropped packet cause by mac filter\n");
                return NF_DROP;
            }
            continue;
        }
    }

    return NF_ACCEPT;
}

/* ============================================================
 *                     PROCFS WRITE HANDLER
 * ============================================================ */

static ssize_t netMonProcWrite(struct file *file, const char __user *buffer, size_t count, loff_t *pos) {
    char *kernelBuffer;
    char action[ACTION_MAX_LEN], value[VALUE_MAX_LEN];
    char type[TYPE_MAX_LEN], interface[IFACE_MAX_LEN];
    char direction[DIRECTION_MAX_LEN];
    int result;

    kernelBuffer = kmalloc(count + 1, GFP_KERNEL); // allocate kernel spcae buffer
    if(!kernelBuffer) {
        pr_err("netmon: Failed to allocate memory for proc write\n");
        return -ENOMEM;
    }

    if(copy_from_user(kernelBuffer, buffer, count) != 0) { // take command from user space to kernel space buffer
        pr_err("netmon: Failed to copy from user\n");
        kfree(kernelBuffer);
        return -EFAULT;
    }
    kernelBuffer[count] = '\0'; // make it normal C string

    if(sscanf(kernelBuffer, "%15s %15s %15s %15s %31s", action, interface, type, direction, value) != 5) { // parsing the user command to variables
        pr_warn("netmon: Invalid command format. Expected 5 parts.\n");
        kfree(kernelBuffer);
        return -EINVAL;
    }

    // Add or Remove rule
    if(strcmp(action, ACTION_ADD) == 0) {
        result = netMonHandleAddRule(interface, type, direction, value);
    } else if(strcmp(action, ACTION_REMOVE) == 0) {
        result = netMonHandleRemoveRule(interface, type, direction, value);
    } else {
        pr_warn("netmon: Unknown action '%s'. Use ADD or REMOVE.\n", action);
        kfree(kernelBuffer);
        return -EINVAL;
    }
    kfree(kernelBuffer);

    if(result != 0)
        return result;

    return count;
}

/* ============================================================
 *                   MODULE INIT / EXIT
 * ============================================================ */

static int __init netMonInit(void) {
    pr_info("netmon: module loaded\n");

    // hook function settings. capturing 
    gNetMonHookOps.hook = netMonPacketHook;
    gNetMonHookOps.hooknum = NF_INET_PRE_ROUTING; // filtering the packets at the point where they have passed simple sanity checks(i.e checksum is OK, etc...)
    gNetMonHookOps.pf = PF_INET; // ipV4
    gNetMonHookOps.priority = NF_IP_PRI_FIRST;

    nf_register_net_hook(&init_net, &gNetMonHookOps);
    pr_info("netfilter hook settings registered");

    gNetMonProcFile = proc_create(PROCFS_NAME, LINUX_PERMISSIONS, NULL, &gNetMonProcOps); // create procfs file under /proc/... for interfacing with the user
    if(gNetMonProcFile == NULL) {
        pr_err("netmon: Failed to create /proc/%s\n", PROCFS_NAME);
        nf_unregister_net_hook(&init_net, &gNetMonHookOps);
        return -ENOMEM;
    }

    pr_info("netmon: Created /proc/%s\n", PROCFS_NAME);
    return 0;
}

static void __exit netMonExit(void) {
    struct NetMonRule *rule;
    struct NetMonRule *temp;

    list_for_each_entry_safe(rule, temp, &gRuleList, list) {
        list_del(&rule->list);
        kfree(rule);
    }
    
    proc_remove(gNetMonProcFile); 
    pr_info("netmon: Removed /proc/%s\n", PROCFS_NAME);

    nf_unregister_net_hook(&init_net, &gNetMonHookOps);
    pr_info("netmon: module unloaded\n");
}

/* ============================================================
 *                     MODULE METADATA
 * ============================================================ */

module_init(netMonInit);
module_exit(netMonExit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Harel Grecht");
MODULE_DESCRIPTION("netmonfw main");
