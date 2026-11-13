package com.google.android.projection.protocol;

/** LiveData: the fuel and odometer reports phone apps read (checks from AwsomeFox/egmp-aa-ev-hmg-api's ModTest). */
public final class LiveDataTest {
    static int fail;

    static void check(String what, boolean ok) {
        System.out.println((ok ? "ok    " : "FAIL  ") + what);
        if (!ok) fail = 1;
    }

    public static void main(String[] a) throws Exception {
        final java.util.List<String> sent = new java.util.ArrayList<String>();
        LiveData.Out out = new LiveData.Out() {
            public void fuel(int percent, int rangeMeters, boolean low) { sent.add("fuel " + percent + " " + rangeMeters + " " + low); }

            public void odometer(double km) { sent.add("odo " + km); }
        };
        LiveData.send(out, 187, 412, 233201);
        check("93.5% shown as 94%, 412 km as m, odometer 0.1 km: " + sent,
                sent.equals(java.util.Arrays.asList("fuel 94 412000 false", "odo 23320.1")));
        sent.clear();
        LiveData.send(out, 19, -1, -1);
        check("9.5% (10%): low; range unknown left out (-1), no odometer: " + sent,
                sent.equals(java.util.Arrays.asList("fuel 10 -1 true")));
        sent.clear();
        LiveData.send(out, -1, 300, -1);
        check("no state of charge: no fuel report: " + sent, sent.isEmpty());
        check("a range past 999 km is unknown", LiveData.fuel(100, 1500)[1] == -1);
        check("200 raw is 100%", LiveData.fuel(200, 0)[0] == 100);
        System.exit(fail);
    }
}
