#ifndef NETMONFW_H
#define NETMONFW_H

#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/module.h>

// librarys that gives access to network packets inside the kernel
#include <linux/netfilter.h>
#include <linux/netfilter_ipv4.h> // hook points
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/inet.h>
#include <linux/tcp.h>
#include <linux/udp.h>
#include <linux/skbuff.h> //network struct to represent a packet

#include <linux/proc_fs.h>
#include <linux/list.h>

#define LINUX_PERMISSIONS 0644 //read and write operations for sudo (Spelling fixed)

#define WORD_SIZE_BYTE 4
#define ACTION_MAX_LEN 16
#define TYPE_MAX_LEN 16
#define IFACE_MAX_LEN 16
#define DIRECTION_MAX_LEN 16
#define VALUE_MAX_LEN 32
#define ETH_MAC_LEN 6

#define RULE_PORT "port"
#define RULE_IP "ip"
#define RULE_MAC "mac"

#define ACTION_ADD "ADD"
#define ACTION_REMOVE "REMOVE"

#define PROCFS_NAME "netMonfilter"

#define NETMONFW_OK 0

// Renamed to PascalCase to identify as a type
enum NetMonDirection {
    FILTER_DEST,
    FILTER_SOURCE,
    FILTER_BOTH,
    FILTER_INVALID = -1,
};

// Renamed to PascalCase to identify as a type
struct NetMonRule {
    char interface[16]; // eth0/eth1
    char type[16]; // ip, port, ...
    int portNumber;
    __be32 ipAddr; //big endian
    unsigned char macAddr[ETH_MAC_LEN];
    enum NetMonDirection direction;
    struct list_head list; // linked list where each cell holes one specifc rule
};

/* ============================================================
 *                    FUNCTION DECLARATIONS
 * ============================================================ */

enum NetMonDirection directionFromString(char direction[DIRECTION_MAX_LEN]);
unsigned int netMonPacketHook(void *priv, struct sk_buff *skb, const struct nf_hook_state *state);
static int parsePortValue(const char *value, int *outPort);
static int ParseIpValue(const char *value, __be32 *outIp);
static int parseMacValue(const char *value, unsigned char outMac[ETH_MAC_LEN]);
static bool ruleExist(struct NetMonRule* rule, char searchInterface[IFACE_MAX_LEN], enum NetMonDirection searchDirection, const char *type);
static int parseRemoveRuleValue(const char *type, const char *value, int *portNumber, __be32 *ipAddr, unsigned char* macAddr);
static bool isMatchingRuleForRemoval(struct NetMonRule *rule, const char *type, int portNumber, __be32 ipAddr, unsigned char macAddr[ETH_MAC_LEN]);
static int fillBaseRuleFields(struct NetMonRule* rule, const char* interface, const char* type, const char* direction);
static int netMonHandleAddRule(char interface[IFACE_MAX_LEN], char type[TYPE_MAX_LEN], char direction[DIRECTION_MAX_LEN], char value[VALUE_MAX_LEN]);
static int netMonHandleRemoveRule(char interface[IFACE_MAX_LEN], char type[TYPE_MAX_LEN], char direction[DIRECTION_MAX_LEN], char value[VALUE_MAX_LEN]);
static bool checkIpFilter(struct NetMonRule *rule, __be32 sourceIp, __be32 destIp);
static bool checkPortFilter(struct NetMonRule *rule, int sourcePort, int destPort);
static bool checkMacFilter(struct NetMonRule *rule, unsigned char sourceMac[ETH_MAC_LEN], unsigned char destMac[ETH_MAC_LEN]);
static ssize_t netMonProcWrite(struct file *file, const char __user *buffer, size_t count, loff_t *pos);



#endif