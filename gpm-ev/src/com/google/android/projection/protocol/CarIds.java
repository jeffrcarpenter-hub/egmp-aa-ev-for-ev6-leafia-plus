package com.google.android.projection.protocol;

import android.util.Log;

import java.io.FileInputStream;
import java.lang.reflect.Field;
import java.security.MessageDigest;
import java.util.Locale;

/**
 * Checks, by name, that this car's framework uses the binder transaction and
 * HEV flag numbers EvCar and Precond send.
 *
 * Those numbers come from the AIDL method order in the car's automotive.jar,
 * so they could differ between cars and firmware. The Ioniq 5 US 260507
 * profile was verified by the SHA-256 of its framework files; other E-GMP cars
 * on Leafia Plus (EV6 US/Canada, Ioniq 5 Canada) have different framework files
 * (different builds), so instead of a file hash we read the constants the
 * framework itself defines (IHEVService$Stub.TRANSACTION_setBattCondEvStation,
 * HEVManager$HEVFlag.EV_RDY, ...) and use a service only when every number we
 * use for it is exactly what the framework says. A car whose numbers differ
 * gets nothing sent, and the log says which name didn't match.
 *
 * Read-only reflection on the boot classpath (automotive.jar); never throws.
 */
final class CarIds {
    private CarIds() {}

    private static final String TAG = "EvCar";

    static final String HEV_STUB = "com.hkmc.hev.IHEVService$Stub";
    static final String HEV_FLAG = "com.hkmc.hev.HEVManager$HEVFlag";
    static final String BCM_STUB = "com.hkmc.bcm.IBCMService$Stub";
    static final String BCM_LISTENER_STUB = "com.hkmc.bcm.IBCMListener$Stub";
    static final String DATC_STUB = "com.hkmc.datc.IDATCService$Stub";
    static final String HSCAN_STUB =
            "com.hkmc.telematics.hscan.tm_interface.ITM_HSCANService$Stub";

    /** Static int field {@code cls.name}, or null when absent/unreadable. */
    static Integer constant(String cls, String name) {
        try {
            Field f = Class.forName(cls).getDeclaredField(name);
            f.setAccessible(true);
            return Integer.valueOf(f.getInt(null));
        } catch (Throwable t) {
            return null;
        }
    }

    /**
     * True when every {cls, name, expected} triple resolves to exactly the
     * expected value. Logs the first mismatch under {@code what}.
     */
    static boolean all(String what, Object[][] expected) {
        for (Object[] e : expected) {
            String cls = (String) e[0];
            String name = (String) e[1];
            int want = ((Integer) e[2]).intValue();
            Integer got = constant(cls, name);
            if (got == null || got.intValue() != want) {
                Log.w(TAG, what + ": " + cls + "." + name + " is "
                        + (got == null ? "missing" : String.valueOf(got))
                        + ", expected " + want + "; not using it on this car");
                return false;
            }
        }
        return true;
    }

    private static Object[] c(String cls, String name, int v) {
        return new Object[] {cls, name, Integer.valueOf(v)};
    }

    // ---- the numbers in use, by name -------------------------------------------

    /** HEV getter (EvCar reads, Precond reads). */
    static final Object[][] HEV_READ = {
        c(HEV_STUB, "TRANSACTION_getHEVStatus", 3),
    };

    /** Everything Precond reads and sends (HEV 3/62/65/66, flags 44/94, BCM 109). */
    static final Object[][] PRECOND = {
        c(HEV_STUB, "TRANSACTION_getHEVStatus", 3),
        c(HEV_STUB, "TRANSACTION_setBattCondEvStation", 62),
        c(HEV_STUB, "TRANSACTION_setBattCondRouteDis", 65),
        c(HEV_STUB, "TRANSACTION_setBattCondRemainTime", 66),
        c(HEV_FLAG, "EV_RDY", 44),
        c(HEV_FLAG, "EV_BATTERYCONDITIONING", 94),
        c(BCM_STUB, "TRANSACTION_getBattCondIndSta", 109),
    };

    /** EvCar's hscan getters. */
    static final Object[][] HSCAN = {
        c(HSCAN_STUB, "TRANSACTION_getCarSpeed", 0x0b),
        c(HSCAN_STUB, "TRANSACTION_getVIN", 0x2f),
        c(HSCAN_STUB, "TRANSACTION_getXEV_Bms_GDS_SOH", 0xd6),
    };

    /** EvCar's climate getters. */
    static final Object[][] DATC = {
        c(DATC_STUB, "TRANSACTION_isUnitCelsius", 0x06),
        c(DATC_STUB, "TRANSACTION_getVRClimateStatus", 0x29),
    };

    /** EvCar's drive-mode listener. */
    static final Object[][] BCM_LISTEN = {
        c(BCM_STUB, "TRANSACTION_registerBCMListener", 1),
        c(BCM_LISTENER_STUB, "TRANSACTION_onDriveModeChanged", 0x11),
    };

    // ---- the verified Ioniq 5 profile ---------------------------------------------

    // SHA-256 of automotive.odex / automotive-service.odex on the Ioniq 5 US
    // 260507 the hardcoded numbers were verified on (gen5w-preconditioning's
    // profile and the original package). On these files every number is
    // trusted as before, so the name check can never turn anything off there.
    static final String IONIQ5_FRAMEWORK_SHA256 =
            "dd72e04bce0a2b4bda1506308ac21f91002c1436553b8156c345cc4313661338";
    static final String IONIQ5_SERVICE_SHA256 =
            "3cf40fb00854c63afa49abea1dad18a0afcbc0dd68b17de9ed7ea3f5aeab4222";

    private static final Object LOCK = new Object();
    private static Boolean sIoniq5, sHev, sPrecond, sHscan, sDatc, sBcm;

    /** KitKat and the framework files of the verified Ioniq 5 profile. */
    static boolean verifiedIoniq5() {
        synchronized (LOCK) {
            if (sIoniq5 == null) {
                boolean ok;
                try {
                    ok = IONIQ5_FRAMEWORK_SHA256.equals(sha256("/system/framework/automotive.odex"))
                            && IONIQ5_SERVICE_SHA256.equals(
                                    sha256("/system/framework/automotive-service.odex"));
                } catch (Throwable t) {
                    Log.w(TAG, "framework hash failed: " + t);
                    ok = false;
                }
                sIoniq5 = Boolean.valueOf(ok);
                Log.i(TAG, "framework: " + (ok ? "verified Ioniq 5 profile"
                        : "not the Ioniq 5 profile; numbers checked by name"));
            }
            return sIoniq5.booleanValue();
        }
    }

    /** verifiedIoniq5() or every name in the set gives the expected number. */
    private static boolean ok(String what, Object[][] set) {
        return verifiedIoniq5() || all(what, set);
    }

    static String sha256(String path) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        FileInputStream in = new FileInputStream(path);
        try {
            byte[] buf = new byte[16384];
            int n;
            while ((n = in.read(buf)) != -1) {
                md.update(buf, 0, n);
            }
        } finally {
            in.close();
        }
        StringBuilder sb = new StringBuilder();
        for (byte x : md.digest()) {
            sb.append(String.format(Locale.US, "%02x", x & 0xff));
        }
        return sb.toString();
    }

    static boolean hevRead() {
        synchronized (LOCK) {
            if (sHev == null) sHev = Boolean.valueOf(ok("HEV status", HEV_READ));
            return sHev.booleanValue();
        }
    }

    private static volatile Object sHevProxy;
    private static volatile java.lang.reflect.Method sHevStatus;

    /**
     * IHEVService.getHEVStatus(flag) through the framework's own interface,
     * by method name: IHEVService$Stub.asInterface(binder).getHEVStatus(flag).
     * Used for battery reads when the transaction number can't be confirmed
     * by name; -1 on any failure.
     */
    static int hevStatusByName(android.os.IBinder b, int flag) {
        try {
            Object proxy = sHevProxy;
            java.lang.reflect.Method m = sHevStatus;
            if (proxy == null || m == null) {
                Class<?> stub = Class.forName(HEV_STUB);
                proxy = stub.getMethod("asInterface", android.os.IBinder.class).invoke(null, b);
                m = Class.forName("com.hkmc.hev.IHEVService").getMethod("getHEVStatus", int.class);
                sHevProxy = proxy;
                sHevStatus = m;
            }
            return ((Integer) m.invoke(proxy, Integer.valueOf(flag))).intValue();
        } catch (Throwable t) {
            sHevProxy = null;
            return -1;
        }
    }

    static boolean precond() {
        synchronized (LOCK) {
            if (sPrecond == null) sPrecond = Boolean.valueOf(ok("preconditioning", PRECOND));
            return sPrecond.booleanValue();
        }
    }

    static boolean hscan() {
        synchronized (LOCK) {
            if (sHscan == null) sHscan = Boolean.valueOf(ok("hscan", HSCAN));
            return sHscan.booleanValue();
        }
    }

    static boolean datc() {
        synchronized (LOCK) {
            if (sDatc == null) sDatc = Boolean.valueOf(ok("climate", DATC));
            return sDatc.booleanValue();
        }
    }

    static boolean bcmListen() {
        synchronized (LOCK) {
            if (sBcm == null) sBcm = Boolean.valueOf(ok("drive mode", BCM_LISTEN));
            return sBcm.booleanValue();
        }
    }
}
