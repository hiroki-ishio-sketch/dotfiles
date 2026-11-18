#!/usr/bin/env osascript -l JavaScript

// 常駐 HUD デーモン（JS）。
// Usage:
//   osascript -l JavaScript keymap-hud.js daemon <htmlPath> <jsonPath> <pidPath> <cmdPath>
// show/hide は cmdPath に "show" / "hide" を書く。

ObjC.import("Cocoa");
ObjC.import("WebKit");

function unwrap(value) {
  return ObjC.unwrap(value);
}

function readText(path) {
  const value = $.NSString.stringWithContentsOfFileEncodingError(
    path,
    $.NSUTF8StringEncoding,
    null
  );
  if (!value) {
    throw new Error(`failed to read: ${path}`);
  }
  return unwrap(value);
}

function writeText(path, text) {
  $.NSString.stringWithString(String(text)).writeToFileAtomicallyEncodingError(
    path,
    true,
    $.NSUTF8StringEncoding,
    null
  );
}

function buildHtmlDocument(html, jsonText) {
  const injection = `<script>window.__KEYMAP_LAYERS__ = ${jsonText};</script>`;
  if (html.indexOf("</head>") !== -1) {
    return html.replace("</head>", `${injection}\n</head>`);
  }
  return `${injection}\n${html}`;
}

function run(argv) {
  if (argv[0] !== "daemon") {
    throw new Error("usage: keymap-hud.js daemon <html> <json> <pid> <cmd>");
  }
  const htmlPath = argv[1];
  const jsonPath = argv[2];
  const pidPath = argv[3];
  const cmdPath = argv[4];

  const html = readText(htmlPath);
  const jsonText = readText(jsonPath);
  JSON.parse(jsonText);
  const documentHtml = buildHtmlDocument(html, jsonText);
  writeText(pidPath, `${$.NSProcessInfo.processInfo.processIdentifier}\n`);
  writeText(cmdPath, "idle\n");

  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  const width = 1080;
  const height = 860;
  const panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(0, 0, width, height),
    $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel,
    $.NSBackingStoreBuffered,
    false
  );
  panel.setLevel($.NSFloatingWindowLevel);
  panel.setOpaque(false);
  panel.setBackgroundColor($.NSColor.clearColor);
  panel.setHasShadow(true);
  panel.setIgnoresMouseEvents(true);
  panel.setCollectionBehavior(
    $.NSWindowCollectionBehaviorCanJoinAllSpaces |
      $.NSWindowCollectionBehaviorStationary |
      $.NSWindowCollectionBehaviorFullScreenAuxiliary
  );

  const config = $.WKWebViewConfiguration.alloc.init;
  const webView = $.WKWebView.alloc.initWithFrameConfiguration(
    $.NSMakeRect(0, 0, width, height),
    config
  );
  // WKWebView の白背景を消し、HTML の透明をそのまま出す。
  webView.setValueForKey(false, "drawsBackground");
  webView.setOpaque(false);
  webView.loadHTMLStringBaseURL(documentHtml, $.NSURL.URLWithString("about:blank"));
  panel.setContentView(webView);
  panel.center;
  panel.orderOut(null);

  let visible = false;
  let lastCmd = "idle";

  function applyCommand(raw) {
    const cmd = String(raw || "").trim();
    if (!cmd || cmd === lastCmd) {
      return;
    }
    lastCmd = cmd;
    if (cmd === "show") {
      panel.orderFrontRegardless();
      visible = true;
    } else if (cmd === "hide") {
      panel.orderOut(null);
      visible = false;
      writeText(cmdPath, "idle\n");
      lastCmd = "idle";
    } else if (cmd === "quit") {
      panel.orderOut(null);
      app.terminate(null);
    }
  }

  // ファイルポーリング。block タイマーは環境によって落ちるため runloop + delayed perform を使う。
  const checker = $.NSObject.alloc.init;
  function tick() {
    try {
      const raw = readText(cmdPath);
      applyCommand(raw);
    } catch (e) {}
    $.NSTimer.scheduledTimerWithTimeIntervalRepeatsBlock(0.03, false, function () {
      tick();
    });
  }

  try {
    tick();
  } catch (error) {
    // タイマーが使えなくても、初回 show 待ちで runloop は回す。
  }

  app.run();
}
