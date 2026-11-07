package com.bedrockhost.app;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.ContentValues;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.MediaStore;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.webkit.CookieManager;
import android.webkit.URLUtil;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.PopupMenu;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLDecoder;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class MainActivity extends Activity {
    private static final int REQ_FILE = 11;
    private static final int REQ_PERMS = 12;
    private static final String OFFLINE_HTML =
            "<html><body style='background:#0e1512;color:#e6efe9;font-family:sans-serif;padding:28px'>"
                    + "<h2>Host desligado</h2>"
                    + "<p>O painel ainda nao esta respondendo.</p>"
                    + "<p>Toque em <b>Ligar host</b> (ou rode <code>bedrock start</code> no Termux). "
                    + "Leva uns 20 segundos e esta tela abre o painel sozinha.</p>"
                    + "<p style='color:#8fa69a'>Primeira vez? Instale o Termux (F-Droid/GitHub) e rode o install.sh do pacote.</p>"
                    + "</body></html>";

    private final Handler ui = new Handler(Looper.getMainLooper());
    private final AtomicBoolean pinging = new AtomicBoolean(false);
    private WebView web;
    private TextView status;
    private ValueCallback<Uri[]> fileCb;
    private boolean panelShown = false;
    private boolean firstTick = true;

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            monitor();
            ui.postDelayed(this, 3000);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().setStatusBarColor(0xFF0E1512);
        buildUi();
        askPermissionsOnce();
        if (Prefs.keepAlive(this)) startKeepAlive();
        showOffline();
    }

    private int dp(int v) {
        return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics());
    }

    private void buildUi() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(0xFF0E1512);

        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.HORIZONTAL);
        bar.setGravity(Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(12), dp(6), dp(8), dp(6));
        bar.setBackgroundColor(0xFF16201B);

        status = new TextView(this);
        status.setTextColor(0xFF8FA69A);
        status.setTextSize(14);
        status.setText("● verificando...");
        bar.addView(status, new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f));

        Button start = new Button(this);
        start.setText("Ligar host");
        start.setAllCaps(false);
        start.setOnClickListener(v -> startHost());
        bar.addView(start);

        Button more = new Button(this);
        more.setText("⋮");
        more.setAllCaps(false);
        more.setOnClickListener(this::showMenu);
        bar.addView(more);

        root.addView(bar, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT));

        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#0e1512"));
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        web.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                String u = request.getUrl().toString();
                if (u.startsWith(Prefs.url(MainActivity.this))) return false;
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, request.getUrl()));
                } catch (ActivityNotFoundException ignored) {
                }
                return true;
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame() && panelShown) {
                    panelShown = false;
                    showOffline();
                }
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView w, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (fileCb != null) fileCb.onReceiveValue(null);
                fileCb = cb;
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                if (p.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE) {
                    i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                }
                try {
                    startActivityForResult(Intent.createChooser(i, "Escolher arquivo"), REQ_FILE);
                } catch (ActivityNotFoundException e) {
                    fileCb = null;
                    return false;
                }
                return true;
            }
        });
        web.setDownloadListener((url, ua, cd, mime, len) -> saveDownload(url, cd, mime));
        root.addView(web, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f));
        setContentView(root);
    }

    private void showOffline() {
        web.loadDataWithBaseURL(null, OFFLINE_HTML, "text/html", "utf-8", null);
    }

    // ---------------------------------------------------------------- monitor
    @Override
    protected void onResume() {
        super.onResume();
        ui.post(tick);
    }

    @Override
    protected void onPause() {
        ui.removeCallbacks(tick);
        super.onPause();
    }

    private void monitor() {
        if (!pinging.compareAndSet(false, true)) return;
        final String base = Prefs.url(this);
        new Thread(() -> {
            final boolean up = Net.ping(base);
            ui.post(() -> {
                pinging.set(false);
                onPingResult(up, base);
            });
        }).start();
    }

    private void onPingResult(boolean up, String base) {
        if (up) {
            status.setText("● Painel ativo");
            status.setTextColor(0xFF3DDC84);
        } else {
            status.setText(TermuxBridge.installed(this) ? "● Host desligado" : "● Termux nao encontrado");
            status.setTextColor(0xFFFF6B6B);
        }
        if (up && !panelShown) {
            panelShown = true;
            web.loadUrl(base);
        } else if (!up && panelShown) {
            panelShown = false;
            showOffline();
        }
        firstTick = false;
    }

    // ---------------------------------------------------------------- acoes
    private void startKeepAlive() {
        Intent s = new Intent(this, KeepAliveService.class);
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(s);
            else startService(s);
        } catch (Exception e) {
            toast("Nao consegui iniciar o monitor: " + e.getMessage());
        }
    }

    private void startHost() {
        if (!TermuxBridge.installed(this)) {
            toast("Termux nao esta instalado (baixe do F-Droid ou do GitHub).");
            return;
        }
        if (!TermuxBridge.hasPermission(this)) {
            requestPermissions(new String[]{TermuxBridge.PERM}, REQ_PERMS);
            toast("Conceda 'Executar comandos no Termux' e toque de novo.");
            return;
        }
        String err = TermuxBridge.bedrock(this, "start");
        toast(err == null ? "Pedido enviado ao Termux. Aguarde ~20s..." : err);
    }

    private void showMenu(View anchor) {
        PopupMenu m = new PopupMenu(this, anchor);
        m.getMenu().add(0, 1, 0, "Parar host (Termux)");
        m.getMenu().add(0, 2, 1, "Abrir Termux");
        m.getMenu().add(0, 3, 2, "Recarregar painel");
        m.getMenu().add(0, 4, 3, "Bateria: liberar este app");
        m.getMenu().add(0, 5, 4, "Bateria: liberar o Termux (lista)");
        m.getMenu().add(0, 6, 5, "Monitor 24/7: " + (Prefs.keepAlive(this) ? "LIGADO" : "desligado"));
        m.getMenu().add(0, 7, 6, "Religar host sozinho: " + (Prefs.autoHeal(this) ? "LIGADO" : "desligado"));
        m.getMenu().add(0, 8, 7, "Endereco do painel");
        m.setOnMenuItemClickListener(item -> {
            switch (item.getItemId()) {
                case 1:
                    String err = TermuxBridge.bedrock(this, "stop");
                    toast(err == null ? "Parando o host (pode levar 1 min)..." : err);
                    break;
                case 2:
                    Intent li = getPackageManager().getLaunchIntentForPackage(TermuxBridge.PKG);
                    if (li != null) startActivity(li);
                    else toast("Termux nao esta instalado.");
                    break;
                case 3:
                    panelShown = false;
                    showOffline();
                    break;
                case 4:
                    PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
                    if (pm.isIgnoringBatteryOptimizations(getPackageName())) {
                        toast("Este app ja esta sem restricao de bateria.");
                    } else {
                        startActivity(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:" + getPackageName())));
                    }
                    break;
                case 5:
                    toast("Procure 'Termux' na lista e escolha 'Nao otimizar'.");
                    startActivity(new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));
                    break;
                case 6:
                    boolean on = !Prefs.keepAlive(this);
                    Prefs.sp(this).edit().putBoolean("keepalive", on).apply();
                    if (on) startKeepAlive();
                    else stopService(new Intent(this, KeepAliveService.class));
                    toast("Monitor 24/7 " + (on ? "ligado" : "desligado"));
                    break;
                case 7:
                    boolean heal = !Prefs.autoHeal(this);
                    Prefs.sp(this).edit().putBoolean("autoheal", heal).apply();
                    toast("Religar host sozinho " + (heal ? "ligado" : "desligado"));
                    break;
                case 8:
                    askUrl();
                    break;
                default:
                    break;
            }
            return true;
        });
        m.show();
    }

    private void askUrl() {
        final EditText et = new EditText(this);
        et.setText(Prefs.url(this));
        new AlertDialog.Builder(this)
                .setTitle("Endereco do painel")
                .setMessage("Ex.: http://127.0.0.1:8080 (mesma porta do painel_port).")
                .setView(et)
                .setNegativeButton("Cancelar", null)
                .setPositiveButton("Salvar", (d, w) -> {
                    String u = et.getText().toString().trim();
                    while (u.endsWith("/")) u = u.substring(0, u.length() - 1);
                    if (!u.startsWith("http://") && !u.startsWith("https://")) {
                        toast("Precisa comecar com http:// ou https://");
                        return;
                    }
                    Prefs.sp(this).edit().putString("url", u).apply();
                    panelShown = false;
                    showOffline();
                })
                .show();
    }

    private void askPermissionsOnce() {
        SharedPreferences sp = Prefs.sp(this);
        if (sp.getBoolean("asked", false)) return;
        sp.edit().putBoolean("asked", true).apply();
        List<String> need = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 33) need.add(Manifest.permission.POST_NOTIFICATIONS);
        if (Build.VERSION.SDK_INT <= 28) need.add(Manifest.permission.WRITE_EXTERNAL_STORAGE);
        if (TermuxBridge.installed(this)) need.add(TermuxBridge.PERM);
        if (!need.isEmpty()) requestPermissions(need.toArray(new String[0]), REQ_PERMS);
    }

    // ---------------------------------------------------------------- upload / download
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_FILE) {
            if (fileCb != null) {
                fileCb.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data));
                fileCb = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    private String fileNameFrom(String url, String cd, String mime) {
        if (cd != null) {
            Matcher m = Pattern.compile("filename\\*=UTF-8''([^;]+)", Pattern.CASE_INSENSITIVE).matcher(cd);
            if (m.find()) {
                try {
                    return URLDecoder.decode(m.group(1).trim().replace("+", "%2B"), "UTF-8");
                } catch (Exception ignored) {
                }
            }
        }
        return URLUtil.guessFileName(url, cd, mime);
    }

    /** Baixa arquivos do painel (backups, logs, pastas .zip) para Downloads/BedrockHost. */
    private void saveDownload(final String url, final String cd, final String mime) {
        final String cookie = CookieManager.getInstance().getCookie(url);
        final String name = fileNameFrom(url, cd, mime).replaceAll("[\\\\/:*?\"<>|]", "_");
        toast("Baixando " + name + "...");
        new Thread(() -> {
            HttpURLConnection c = null;
            try {
                c = (HttpURLConnection) new URL(url).openConnection();
                if (cookie != null) c.setRequestProperty("Cookie", cookie);
                c.setConnectTimeout(5000);
                if (c.getResponseCode() != 200) throw new Exception("HTTP " + c.getResponseCode());
                InputStream in = c.getInputStream();
                OutputStream out;
                Uri uri = null;
                if (Build.VERSION.SDK_INT >= 29) {
                    ContentValues v = new ContentValues();
                    v.put(MediaStore.Downloads.DISPLAY_NAME, name);
                    v.put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream");
                    v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/BedrockHost");
                    v.put(MediaStore.Downloads.IS_PENDING, 1);
                    uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                    if (uri == null) throw new Exception("nao foi possivel criar o arquivo");
                    out = getContentResolver().openOutputStream(uri);
                } else {
                    File dir = new File(Environment.getExternalStoragePublicDirectory(
                            Environment.DIRECTORY_DOWNLOADS), "BedrockHost");
                    dir.mkdirs();
                    out = new FileOutputStream(new File(dir, name));
                }
                byte[] buf = new byte[1 << 16];
                int n;
                while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                out.close();
                if (uri != null) {
                    ContentValues v2 = new ContentValues();
                    v2.put(MediaStore.Downloads.IS_PENDING, 0);
                    getContentResolver().update(uri, v2, null, null);
                }
                runOnUiThread(() -> toast("Salvo em Downloads/BedrockHost/" + name));
            } catch (Exception e) {
                runOnUiThread(() -> toast("Falha no download: " + e.getMessage()));
            } finally {
                if (c != null) c.disconnect();
            }
        }).start();
    }

    private void toast(String s) {
        Toast.makeText(this, s, Toast.LENGTH_LONG).show();
    }

    @Override
    public void onBackPressed() {
        moveTaskToBack(true); // mantem o app (e o monitor) vivo em segundo plano
    }

    @Override
    protected void onDestroy() {
        ui.removeCallbacks(tick);
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
