package com.bedrockhost.app;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Build;

/** Pede ao Termux (via RUN_COMMAND) para executar o comando 'bedrock'. */
final class TermuxBridge {
    static final String PKG = "com.termux";
    static final String PERM = "com.termux.permission.RUN_COMMAND";
    private static final String PREFIX = "/data/data/com.termux/files/usr";
    private static final String HOME = "/data/data/com.termux/files/home";

    private TermuxBridge() {}

    static boolean installed(Context c) {
        try {
            c.getPackageManager().getPackageInfo(PKG, 0);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    static boolean hasPermission(Context c) {
        return c.checkSelfPermission(PERM) == PackageManager.PERMISSION_GRANTED;
    }

    /** Executa "bedrock <sub>" em segundo plano no Termux. Retorna null se ok, ou a mensagem de erro. */
    static String bedrock(Context c, String sub) {
        if (!installed(c)) return "Termux nao esta instalado";
        if (!hasPermission(c)) return "Sem permissao 'Executar comandos no Termux'";
        try {
            Intent i = new Intent("com.termux.RUN_COMMAND");
            i.setClassName(PKG, "com.termux.app.RunCommandService");
            i.putExtra("com.termux.RUN_COMMAND_PATH", PREFIX + "/bin/bash");
            i.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", new String[]{"-lc", PREFIX + "/bin/bedrock " + sub});
            i.putExtra("com.termux.RUN_COMMAND_WORKDIR", HOME);
            i.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true);
            if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i);
            else c.startService(i);
            return null;
        } catch (Exception e) {
            return e.getClass().getSimpleName() + ": " + e.getMessage()
                    + " (confira 'allow-external-apps = true' em ~/.termux/termux.properties)";
        }
    }
}
