import javax.microedition.media.Player;

/** MMAPI providers can leave a player unrealized while their output is disabled. */
final class GF3AudioDevice {
    static boolean ready(int channelState,Player player) {
        return channelState==1 && player!=null && player.getState()>=Player.REALIZED;
    }
}
