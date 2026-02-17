document.addEventListener("DOMContentLoaded", () => {
  const sessionStatus = document.getElementById("session-status");
  const blockedCount = document.getElementById("blocked-count");
  const refreshBtn = document.getElementById("refresh-btn");

  function updateUI(status) {
    if (status.isActive) {
      sessionStatus.textContent = "Active";
      sessionStatus.className = "status-value status-active";
    } else {
      sessionStatus.textContent = "Inactive";
      sessionStatus.className = "status-value status-inactive";
    }
    blockedCount.textContent = status.blockedCount || 0;
  }

  // Get initial status
  browser.runtime.sendMessage({ action: "getStatus" }, (response) => {
    if (response) updateUI(response);
  });

  // Refresh button
  refreshBtn.addEventListener("click", () => {
    refreshBtn.textContent = "Refreshing...";
    refreshBtn.disabled = true;

    browser.runtime.sendMessage({ action: "refreshRules" }, (response) => {
      if (response) updateUI(response);
      refreshBtn.textContent = "Refresh";
      refreshBtn.disabled = false;
    });
  });
});
