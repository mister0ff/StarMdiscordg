package com.bedrockhost.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;

/**
 * Servico em primeiro plano: segura um wake lock, monitora o painel e,
 * se ele ficar fora do ar por 90s, pede ao Termux para religar o host.
 */
public class KeepAliveService extends Service {
    static final String ACTION_STOP = "com.bedrockhost.app.STOP";
    private static final String CHANNEL = "keepalive";
    private static final int NOTIF_ID = 1;

    private volatile boolean running = false;
    private Thread worker;
    private PowerManager.WakeLock wakeLock;
    private String lastText = "";

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            Prefs.sp(this).edit().putBoolean("keepalive", false).apply();
            stopSelf();
            return START_NOT_STICKY;
        }
        createChannel();
        Notification n = buildNotification("Monitorando o servidor...");
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE);
        } else {
            startForeground(NOTIF_ID, n);
        }
        if (wakeLock == null) {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BedrockHost:keepalive");
            wakeLock.acquire();
        }
        if (!running) {
            running = true;
            worker = new Thread(this::loop, "bh-monitor");
            worker.start();
        }
        return START_STICKY;
    }

    private void loop() {
        long downSince = 0;
        long lastHeal = 0;
        while (running) {
            String base = Prefs.url(this);
            boolean up = Net.ping(base);
            long now = System.currentTimeMillis();
            String text;
            if (up) {
                downSince = 0;
                text = "Painel ativo - servidor no ar";
            } else {
                if (downSince == 0) downSince = now;
                long secs = (now - downSince) / 1000;
                text = "Painel fora do ar ha " + secs + "s";
                if (Prefs.autoHeal(this) && secs >= 90 && now - lastHeal > 180000L) {
                    lastHeal = now;
                    String err = TermuxBridge.bedrock(this, "start");
                    text = err == null ? "Religando o host via Termux..." : "Falha ao religar: " + err;
                }
            }
            if (!text.equals(lastText)) {
                lastText = text;
                NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                nm.notify(NOTIF_ID, buildNotification(text));
            }
            try {
                Thread.sleep(5000);
            } catch (InterruptedException e) {
                return;
            }
        }
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel ch = new NotificationChannel(CHANNEL, "Monitor do servidor",
                    NotificationManager.IMPORTANCE_LOW);
            ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).createNotificationChannel(ch);
        }
    }

    private Notification buildNotification(String text) {
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class),
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Intent stop = new Intent(this, KeepAliveService.class).setAction(ACTION_STOP);
        PendingIntent stopPi = PendingIntent.getService(this, 1, stop,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder b = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(this, CHANNEL)
                : new Notification.Builder(this);
        b.setSmallIcon(R.drawable.ic_stat)
                .setContentTitle("Bedrock Host")
                .setContentText(text)
                .setContentIntent(open)
                .setOngoing(true)
                .addAction(0, "Parar monitor", stopPi);
        return b.build();
    }

    @Override
    public void onDestroy() {
        running = false;
        if (worker != null) worker.interrupt();
        if (wakeLock != null && wakeLock.isHeld()) wakeLock.release();
        super.onDestroy();
    }
}
