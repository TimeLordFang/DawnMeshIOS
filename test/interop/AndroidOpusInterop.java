import java.nio.file.*;
import java.util.Arrays;
import io.github.jaredmdobson.concentus.*;

// Same library/settings used by DawnMesh Android's OpusCodec.kt.
public class AndroidOpusInterop {
  public static void main(String[] args) throws Exception {
    if (args[0].equals("encode")) {
      OpusEncoder encoder = new OpusEncoder(16000, 1, OpusApplication.OPUS_APPLICATION_VOIP);
      encoder.setBitrate(24000); encoder.setComplexity(5);
      encoder.setSignalType(OpusSignal.OPUS_SIGNAL_VOICE);
      encoder.setUseVBR(true); encoder.setUseConstrainedVBR(true); encoder.setUseDTX(true);
      short[] pcm = new short[320];
      for (int i=0;i<320;i++) pcm[i] = (short)(Math.sin(i*0.13)*12000);
      byte[] packet = new byte[512];
      int length = encoder.encode(pcm, 0, 320, packet, 0, packet.length);
      Files.write(Path.of(args[1]), Arrays.copyOf(packet, length));
      System.out.println("Android Concentus encoded 320 samples: " + length + " bytes");
    } else {
      byte[] packet = Files.readAllBytes(Path.of(args[1]));
      short[] pcm = new short[320];
      OpusDecoder decoder = new OpusDecoder(16000, 1);
      int length = decoder.decode(packet, 0, packet.length, pcm, 0, 320, false);
      if (length != 320) throw new AssertionError("Unexpected samples: " + length);
      boolean audible = false;
      for (short sample : pcm) if (sample != 0) audible = true;
      if (!audible) throw new AssertionError("Decoded silence");
      System.out.println("Android Concentus decoded iOS Opus: 320 samples");
    }
  }
}
