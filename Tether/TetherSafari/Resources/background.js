// Tether Safari Extension - Background Service Worker
// Receives blocklist rules from the native app via native messaging
// and applies them as declarativeNetRequest dynamic rules.

let currentRuleIds = [];
let isSessionActive = false;

// Poll the native app for rules every 30 seconds
const POLL_INTERVAL_MS = 30000;

async function fetchRulesFromApp() {
  try {
    const response = await browser.runtime.sendNativeMessage("com.willhammond.tether.safari", {
      action: "getRules"
    });

    if (response && response.rules) {
      isSessionActive = response.isActive || false;
      await applyRules(response.rules);
    }
  } catch (error) {
    console.error("Tether: Failed to fetch rules from native app:", error);
  }
}

async function applyRules(rules) {
  try {
    // Remove existing dynamic rules
    if (currentRuleIds.length > 0) {
      await browser.declarativeNetRequest.updateDynamicRules({
        removeRuleIds: currentRuleIds
      });
    }

    if (!isSessionActive || rules.length === 0) {
      currentRuleIds = [];
      updateBadge(0);
      return;
    }

    // Add new rules
    const validRules = rules.map((rule, index) => ({
      id: index + 1,
      priority: rule.priority || 1,
      action: rule.action,
      condition: rule.condition
    }));

    await browser.declarativeNetRequest.updateDynamicRules({
      addRules: validRules
    });

    currentRuleIds = validRules.map(r => r.id);
    updateBadge(currentRuleIds.length);
  } catch (error) {
    console.error("Tether: Failed to apply rules:", error);
  }
}

function updateBadge(count) {
  if (count > 0) {
    browser.action.setBadgeText({ text: String(count) });
    browser.action.setBadgeBackgroundColor({ color: "#FF6B6B" });
  } else {
    browser.action.setBadgeText({ text: "" });
  }
}

// Initial fetch
fetchRulesFromApp();

// Set up polling
setInterval(fetchRulesFromApp, POLL_INTERVAL_MS);

// Listen for messages from popup
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.action === "getStatus") {
    sendResponse({
      isActive: isSessionActive,
      blockedCount: currentRuleIds.length
    });
  } else if (message.action === "refreshRules") {
    fetchRulesFromApp().then(() => {
      sendResponse({
        isActive: isSessionActive,
        blockedCount: currentRuleIds.length
      });
    });
    return true; // Async response
  }
});
