// PyreWeb LiveView connector
// Phoenix JS dependencies (phoenix.js, phoenix_html.js, phoenix_live_view.js)
// are prepended at compile time by PyreWeb.Assets.

let socketPath = document.querySelector("html").getAttribute("phx-socket") || "/live"
let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

Hooks.PasteUpload = {
  mounted() {
    this.handlePaste = (e) => {
      const files = e.clipboardData?.files;
      if (!files?.length) return;

      const input = this.el.querySelector("input[type=file]");
      if (!input) return;

      const dt = new DataTransfer();
      for (const f of files) {
        if (f.type.startsWith("image/")) dt.items.add(f);
      }
      if (dt.files.length) {
        input.files = dt.files;
        input.dispatchEvent(new Event("input", { bubbles: true }));
      }
    };
    window.addEventListener("paste", this.handlePaste);
  },
  destroyed() {
    window.removeEventListener("paste", this.handlePaste);
  }
}

Hooks.Notifications = {
  mounted() {
    this.toastContainer = document.createElement("div")
    this.toastContainer.className = "toast toast-end toast-bottom z-50"
    this.toastContainer.style.pointerEvents = "none"
    document.body.appendChild(this.toastContainer)

    this.setupBell()

    this.handleEvent("pyre:notify", (payload) => {
      this.showToast(payload)
      this.maybeShowSystemNotification(payload)
    })
  },

  destroyed() {
    if (this.toastContainer && this.toastContainer.parentNode) {
      this.toastContainer.remove()
    }
  },

  setupBell() {
    const bell = document.getElementById("pyre-notification-bell")
    if (!bell) return

    this.updateBellState(bell)

    bell.addEventListener("click", () => {
      if (typeof Notification === "undefined") return

      const perm = Notification.permission

      if (perm === "default") {
        Notification.requestPermission().then((result) => {
          if (result === "granted") {
            localStorage.setItem("pyre:notifications", "enabled")
          }
          this.updateBellState(bell)
        })
      } else if (perm === "granted") {
        const current = localStorage.getItem("pyre:notifications")
        localStorage.setItem("pyre:notifications", current === "enabled" ? "disabled" : "enabled")
        this.updateBellState(bell)
      }
    })
  },

  updateBellState(bell) {
    const supported = typeof Notification !== "undefined"
    const perm = supported ? Notification.permission : "unsupported"
    const enabled = localStorage.getItem("pyre:notifications") === "enabled"
    const indicator = bell.querySelector("[data-notification-indicator]")

    if (!supported) {
      bell.classList.add("btn-disabled")
      bell.title = "Notifications not supported in this browser"
    } else if (perm === "granted" && enabled) {
      bell.classList.remove("btn-disabled")
      if (indicator) indicator.classList.remove("hidden")
      bell.title = "Desktop notifications enabled (click to disable)"
    } else if (perm === "denied") {
      bell.classList.remove("btn-disabled")
      if (indicator) indicator.classList.add("hidden")
      bell.title = "Notifications blocked \u2014 update in browser settings"
    } else {
      bell.classList.remove("btn-disabled")
      if (indicator) indicator.classList.add("hidden")
      bell.title = "Enable desktop notifications"
    }
  },

  showToast({ title, body, level }) {
    const alertClass = {
      success: "alert-success",
      error: "alert-error",
      warning: "alert-warning",
      info: "alert-info"
    }[level] || "alert-info"

    const toast = document.createElement("div")
    toast.className = `alert ${alertClass} shadow-lg mb-2 transition-opacity duration-300`
    toast.style.pointerEvents = "auto"
    toast.style.maxWidth = "24rem"

    const titleEl = document.createElement("span")
    titleEl.className = "font-semibold text-sm"
    titleEl.textContent = title

    const bodyEl = document.createElement("span")
    bodyEl.className = "text-xs block"
    bodyEl.textContent = body

    const wrapper = document.createElement("div")
    wrapper.appendChild(titleEl)
    wrapper.appendChild(bodyEl)
    toast.appendChild(wrapper)

    this.toastContainer.appendChild(toast)

    setTimeout(() => {
      toast.style.opacity = "0"
      setTimeout(() => toast.remove(), 300)
    }, 5000)
  },

  maybeShowSystemNotification({ title, body, tag }) {
    if (typeof Notification === "undefined") return
    if (Notification.permission !== "granted") return
    if (localStorage.getItem("pyre:notifications") !== "enabled") return

    const n = new Notification(title, {
      body: body,
      tag: tag || "pyre-notification"
    })

    n.onclick = () => {
      window.focus()
      n.close()
    }
  }
}

let liveSocket = new LiveView.LiveSocket(socketPath, Phoenix.Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks
})

// WebSocket -> LongPoll fallback
const socket = liveSocket.socket
const originalOnConnError = socket.onConnError
let fallbackToLongPoll = true

socket.onOpen(() => { fallbackToLongPoll = false })

socket.onConnError = (...args) => {
  if (fallbackToLongPoll) {
    fallbackToLongPoll = false
    socket.disconnect(null, 3000)
    socket.transport = Phoenix.LongPoll
    socket.connect()
  } else {
    originalOnConnError.apply(socket, args)
  }
}

liveSocket.connect()

window.liveSocket = liveSocket
