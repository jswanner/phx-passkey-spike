// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"

function arrayBufferToBase64(arrayBuffer) {
  return btoa(String.fromCharCode.apply(null, new Uint8Array(arrayBuffer)))
}

const hooks = {
  createCredential: {
    async createCredential() {
      const json = await this.pushEvent("generate_credential_registration", {});
      const publicKey = await PublicKeyCredential.parseCreationOptionsFromJSON(json);
      const credential = await navigator.credentials.create({ publicKey });
      await this.pushEvent("store_credential", {
        credential: {
          ...credential,
          clientExtensionResults: credential.getClientExtensionResults(),
          rawId: arrayBufferToBase64(credential.rawId),
          response: {
            ...credential.response,
            attestationObject: arrayBufferToBase64(credential.response.attestationObject),
            authenticatorData: arrayBufferToBase64(credential.response.getAuthenticatorData()),
            clientDataJSON: arrayBufferToBase64(credential.response.clientDataJSON),
            publicKey: arrayBufferToBase64(credential.response.getPublicKey()),
            publicKeyAlgorithm: credential.response.getPublicKeyAlgorithm(),
            transports: credential.response.getTransports(),
          }
        }
      });
    },
    destroyed() {
      document.removeEventListener("create_credential", this.createCredential, false);
    },
    async mounted() {
      this.createCredential = this.createCredential.bind(this);
      document.addEventListener("create_credential", this.createCredential, false);
      if (window.PublicKeyCredential && PublicKeyCredential.getClientCapabilities) {
        const capabilities = await PublicKeyCredential.getClientCapabilities();
        await this.pushEvent("update_capabilities", capabilities);
      }
    }
  },
  getCredential: {
    async getCredential() {
      const { signal } = controller = new AbortController();
      const abort = () => controller.abort();
      document.addEventListener("abort_get_credential", abort, false);
      const json = await this.pushEvent("generate_credential_authentication", {});
      const publicKey = await PublicKeyCredential.parseRequestOptionsFromJSON(json);
      try {
        const credential = await navigator.credentials.get({ mediation: "conditional", publicKey, signal });
        await this.pushEvent("authenticate_credential", {
          credential: {
            ...credential,
            clientExtensionResults: credential.getClientExtensionResults(),
            rawId: arrayBufferToBase64(credential.rawId),
            response: {
              ...credential.response,
              authenticatorData: arrayBufferToBase64(credential.response.authenticatorData),
              clientDataJSON: arrayBufferToBase64(credential.response.clientDataJSON),
              signature: arrayBufferToBase64(credential.response.signature),
              userHandle: arrayBufferToBase64(credential.response.userHandle),
            }
          }
        });
      } catch (_error) { }
      document.removeEventListener("abort_get_credential", abort);
    },
    async mounted() {
      if (window.PublicKeyCredential && PublicKeyCredential.getClientCapabilities) {
        const capabilities = await PublicKeyCredential.getClientCapabilities();

        if (capabilities.conditionalGet) {
          this.getCredential();
        }
      }
    }
  }
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  hooks,
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken }
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({ detail: reloader }) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if (keyDown === "c") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if (keyDown === "d") {
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

