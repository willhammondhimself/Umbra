document.addEventListener("DOMContentLoaded", async () => {
  const loginView = document.getElementById("login-view");
  const statusView = document.getElementById("status-view");
  const loginBtn = document.getElementById("login-btn");
  const logoutBtn = document.getElementById("logout-btn");
  const refreshBtn = document.getElementById("refresh-btn");
  const loginError = document.getElementById("login-error");
  const sessionStatus = document.getElementById("session-status");
  const blockedCount = document.getElementById("blocked-count");

  // Check if logged in
  const { authToken } = await chrome.storage.local.get("authToken");
  if (authToken) {
    showStatusView();
  } else {
    showLoginView();
  }

  function showLoginView() {
    loginView.classList.remove("hidden");
    statusView.classList.add("hidden");
  }

  function showStatusView() {
    loginView.classList.add("hidden");
    statusView.classList.remove("hidden");
    refreshStatus();
  }

  function refreshStatus() {
    chrome.runtime.sendMessage({ action: "getStatus" }, (response) => {
      if (response) {
        updateStatusUI(response);
      }
    });
  }

  function updateStatusUI(status) {
    if (status.isActive) {
      sessionStatus.textContent = "Active";
      sessionStatus.className = "status-value status-active";
    } else {
      sessionStatus.textContent = "Inactive";
      sessionStatus.className = "status-value status-inactive";
    }
    blockedCount.textContent = status.blockedCount || 0;
  }

  // Login
  loginBtn.addEventListener("click", async () => {
    const baseUrl = document.getElementById("server-url").value.replace(/\/$/, "");
    const email = document.getElementById("login-email").value;
    const password = document.getElementById("login-password").value;

    if (!email || !password) {
      showError("Please enter email and password.");
      return;
    }

    loginBtn.textContent = "Signing in...";
    loginBtn.disabled = true;
    loginError.classList.add("hidden");

    try {
      const response = await fetch(`${baseUrl}/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          provider: "email",
          email: email,
          password: password
        })
      });

      if (!response.ok) {
        const data = await response.json().catch(() => ({}));
        throw new Error(data.detail || "Login failed");
      }

      const data = await response.json();
      chrome.runtime.sendMessage({
        action: "login",
        token: data.access_token,
        baseUrl: baseUrl
      }, () => {
        showStatusView();
      });
    } catch (error) {
      showError(error.message || "Failed to connect to server");
    } finally {
      loginBtn.textContent = "Sign In";
      loginBtn.disabled = false;
    }
  });

  function showError(msg) {
    loginError.textContent = msg;
    loginError.classList.remove("hidden");
  }

  // Logout
  logoutBtn.addEventListener("click", () => {
    chrome.runtime.sendMessage({ action: "logout" }, () => {
      showLoginView();
    });
  });

  // Refresh
  refreshBtn.addEventListener("click", () => {
    refreshBtn.textContent = "Refreshing...";
    refreshBtn.disabled = true;
    chrome.runtime.sendMessage({ action: "refresh" }, (response) => {
      if (response) updateStatusUI(response);
      refreshBtn.textContent = "Refresh";
      refreshBtn.disabled = false;
    });
  });
});
