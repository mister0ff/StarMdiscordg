package com.bedrockhost.app;

import android.content.Context;
import android.content.SharedPreferences;

final class Prefs {
    private Prefs() {}

    static SharedPreferences sp(Context c) {
        return c.getSharedPreferences("bh", Context.MODE_PRIVATE);
    }

    static String url(Context c) {
        return sp(c).getString("url", "http://127.0.0.1:8080");
    }

    static boolean keepAlive(Context c) {
        return sp(c).getBoolean("keepalive", true);
    }

    static boolean autoHeal(Context c) {
        return sp(c).getBoolean("autoheal", true);
    }
}
