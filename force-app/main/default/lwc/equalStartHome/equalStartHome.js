import { LightningElement } from "lwc";

export default class EqualStartHome extends LightningElement {
  connectedCallback() {
    this.loadFonts();
  }

  loadFonts() {
    const href =
      "https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600;9..144,700&family=Public+Sans:wght@400;500;600;700&family=IBM+Plex+Mono:wght@500&display=swap";
    if (!document.querySelector(`link[href="${href}"]`)) {
      const link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = href;
      document.head.appendChild(link);
    }
  }

  // Launch the Equal Grant embedded messaging window; falls back silently to
  // the floating widget that is always available in the corner.
  openChat() {
    try {
      const bs = window.embeddedservice_bootstrap;
      if (bs && bs.utilAPI && typeof bs.utilAPI.launchChat === "function") {
        bs.utilAPI.launchChat();
        return;
      }
      if (window.embedded_svc && window.embedded_svc.bootstrapEmbeddedService) {
        window.embedded_svc.bootstrapEmbeddedService();
      }
    } catch (e) {
      // No-op: the floating Equal Grant widget remains available.
    }
  }
}