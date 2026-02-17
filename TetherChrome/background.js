// Tether Chrome Extension - Background Service Worker
// Polls the Tether backend API for blocklist and session state,
// then applies declarativeNetRequest rules to block sites during focus sessions.

const BLOCKLIST_POLL_INTERVAL_MIN = 5;
const SESSION_POLL_INTERVAL_SEC = 30;

let currentRuleIds = [];
let isSessionActive = false;
let cachedBlocklist = [];

// Get stored API base URL and JWT token
async function getConfig() {
  const result = await chrome.storage.local.get(["apiBaseUrl", "authToken"]);
  return {
    baseUrl: result.apiBaseUrl || "https://api.tether.app",
    token: result.authToken || null
  };
}

async function apiFetch(path) {
  const config = await getConfig();
  if (!config.token) return null;

  try {
    const response = await fetch(`${config.baseUrl}${path}`, {
      headers: {
        "Authorization": `Bearer ${config.token}`,
        "Content-Type": "application/json"
      }
    });
    if (response.status === 401) {
      // Token expired — clear it
      await chrome.storage.local.remove("authToken");
      updateBadge(0, false);
      return null;
    }
    if (!response.ok) return null;
    return await response.json();
  } catch (error) {
    console.error("Tether: API fetch error:", error);
    return null;
  }
}

async function fetchBlocklist() {
  const data = await apiFetch("/blocklist");
  if (data && Array.isArray(data)) {
    cachedBlocklist = data;
    await applyRules();
  }
}

async function fetchSessionState() {
  const data = await apiFetch("/sessions/active");
  const wasActive = isSessionActive;
  isSessionActive = data !== null && data.id !== undefined;

  if (wasActive !== isSessionActive) {
    await applyRules();
  }
  updateBadge(currentRuleIds.length, isSessionActive);
}

async function applyRules() {
  try {
    // Remove existing dynamic rules
    if (currentRuleIds.length > 0) {
      await chrome.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: currentRuleIds
      });
      currentRuleIds = [];
    }

    if (!isSessionActive || cachedBlocklist.length === 0) {
      updateBadge(0, isSessionActive);
      return;
    }

    // Convert blocklist items to DNR rules
    const rules = cachedBlocklist
      .filter(item => item.is_enabled && item.domain)
      .map((item, index) => {
        const ruleId = index + 1;
        const actionType = item.block_mode === 0 ? "redirect" : "block";
        const rule = {
          id: ruleId,
          priority: 1,
          action: { type: actionType },
          condition: {
            urlFilter: `||${item.domain}`,
            resourceTypes: ["main_frame"]
          }
        };

        if (actionType === "redirect") {
          rule.action.redirect = {
            extensionPath: `/blocked.html?domain=${encodeURIComponent(item.domain)}`
          };
        }

        return rule;
      });

    if (rules.length > 0) {
      await chrome.declarativeNetRequest.updateDynamicRules({
        addRules: rules
      });
      currentRuleIds = rules.map(r => r.id);
    }

    updateBadge(currentRuleIds.length, isSessionActive);
  } catch (error) {
    console.error("Tether: Failed to apply rules:", error);
  }
}

function updateBadge(count, active) {
  if (active && count > 0) {
    chrome.action.setBadgeText({ text: String(count) });
    chrome.action.setBadgeBackgroundColor({ color: "#FF6B6B" });
  } else if (active) {
    chrome.action.setBadgeText({ text: "●" });
    chrome.action.setBadgeBackgroundColor({ color: "#34C759" });
  } else {
    chrome.action.setBadgeText({ text: "" });
  }
}

// Set up alarms for polling
chrome.alarms.create("pollBlocklist", { periodInMinutes: BLOCKLIST_POLL_INTERVAL_MIN });
chrome.alarms.create("pollSession", { periodInMinutes: SESSION_POLL_INTERVAL_SEC / 60 });

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "pollBlocklist") fetchBlocklist();
  if (alarm.name === "pollSession") fetchSessionState();
});

// Initial fetch
fetchBlocklist();
fetchSessionState();

// Listen for messages from popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === "getStatus") {
    sendResponse({
      isLoggedIn: true,
      isActive: isSessionActive,
      blockedCount: currentRuleIds.length
    });
  } else if (message.action === "login") {
    chrome.storage.local.set({
      authToken: message.token,
      apiBaseUrl: message.baseUrl || "https://api.tether.app"
    }, () => {
      fetchBlocklist();
      fetchSessionState();
      sendResponse({ success: true });
    });
    return true;
  } else if (message.action === "logout") {
    chrome.storage.local.remove(["authToken", "apiBaseUrl"], async () => {
      isSessionActive = false;
      cachedBlocklist = [];
      await applyRules();
      sendResponse({ success: true });
    });
    return true;
  } else if (message.action === "refresh") {
    Promise.all([fetchBlocklist(), fetchSessionState()]).then(() => {
      sendResponse({
        isActive: isSessionActive,
        blockedCount: currentRuleIds.length
      });
    });
    return true;
  }
});
