import 'dart:math';

class TextProcessor {
  static const int _targetChunkSize = 1000;
  static const int _maxChunkSize = 1500; // Allow exceeding target to preserve sentences
  static const List<String> _sentenceTerminators = ['.', '!', '?', '\n'];
  static const List<String> _safeChars = ['.', '\n', '!', '?', '"', '"'];

  /// Splits text into chunks, strictly respecting sentence boundaries.
  /// Will exceed [targetSize] up to [_maxChunkSize] to avoid cutting sentences.
  static List<String> smartSplit(String text,
      {int targetSize = _targetChunkSize}) {
    final List<String> chunks = [];
    int currentPos = 0;
    final int length = text.length;

    while (currentPos < length) {
      int endPos = currentPos + targetSize;

      if (endPos >= length) {
        endPos = length;
      } else {
        // First, try to find a sentence terminator by looking BACK from target
        int safeSpot = _findSentenceTerminatorBackward(
            text, endPos, currentPos, targetSize ~/ 2);

        if (safeSpot != -1) {
          endPos = safeSpot;
        } else {
          // No terminator found looking back - look FORWARD to complete the sentence
          // This allows chunks to exceed targetSize but stay under maxChunkSize
          safeSpot = _findSentenceTerminatorForward(
              text, endPos, min(currentPos + _maxChunkSize, length));

          if (safeSpot != -1) {
            endPos = safeSpot;
          } else {
            // Still no terminator - we're in a very long sentence
            // As last resort, find the end of current sentence even if it exceeds max
            safeSpot = _findSentenceTerminatorForward(text, endPos, length);
            if (safeSpot != -1 && safeSpot - currentPos <= _maxChunkSize * 2) {
              endPos = safeSpot;
            }
            // If sentence is extremely long, we have no choice but to cut at max
            // This should be rare in normal text
          }
        }
      }

      // Safety check: Ensure we always make progress to avoid infinite loop
      if (endPos <= currentPos) {
        endPos = min(currentPos + targetSize, length);
      }

      final String chunk = text.substring(currentPos, endPos).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      currentPos = endPos;
      // Skip any leading whitespace for next chunk
      while (currentPos < length && text[currentPos] == ' ') {
        currentPos++;
      }
    }

    return chunks;
  }

  /// Find sentence terminator looking backward from position
  static int _findSentenceTerminatorBackward(
      String text, int fromPos, int minPos, int maxLookBack) {
    for (int i = 0; i < maxLookBack; i++) {
      final int checkPos = fromPos - i;
      if (checkPos <= minPos) break;

      final String char = text[checkPos];
      if (_sentenceTerminators.contains(char)) {
        // Include closing quotes after terminator
        int endPos = checkPos + 1;
        while (endPos < text.length &&
            (text[endPos] == '"' || text[endPos] == '"' || text[endPos] == "'")) {
          endPos++;
        }
        return endPos;
      }
    }
    return -1;
  }

  /// Find sentence terminator looking forward from position
  static int _findSentenceTerminatorForward(
      String text, int fromPos, int maxPos) {
    for (int i = fromPos; i < maxPos; i++) {
      final String char = text[i];
      if (_sentenceTerminators.contains(char)) {
        // Include closing quotes after terminator
        int endPos = i + 1;
        while (endPos < text.length &&
            (text[endPos] == '"' || text[endPos] == '"' || text[endPos] == "'")) {
          endPos++;
        }
        return endPos;
      }
    }
    return -1;
  }

  /// Extracts the last 1-2 sentences from a chunk for context passing
  static String extractLastSentences(String text, {int maxLength = 200}) {
    if (text.isEmpty) return "";

    final trimmed = text.trim();
    if (trimmed.length <= maxLength) return trimmed;

    // Find sentence boundaries from the end
    int sentenceCount = 0;
    int cutPos = trimmed.length;

    for (int i = trimmed.length - 2; i >= 0; i--) {
      final char = trimmed[i];
      if (_sentenceTerminators.contains(char)) {
        sentenceCount++;
        if (sentenceCount >= 2 || trimmed.length - i >= maxLength) {
          cutPos = i + 1;
          break;
        }
      }
    }

    // If we couldn't find sentence boundaries, just take the last maxLength chars
    if (cutPos == trimmed.length) {
      cutPos = max(0, trimmed.length - maxLength);
    }

    return trimmed.substring(cutPos).trim();
  }

  /// Creates a sample text for analysis by taking head, mid, and tail sections.
  static String createSample(String text) {
    const int headSize = 4000;
    const int midSize = 3000;
    const int tailSize = 3000;
    final int totalLen = text.length;

    if (totalLen <= (headSize + midSize + tailSize)) {
      return text;
    }

    String combinedSample = "";

    // 1. Head
    int safeHeadEnd = _findSafeCutBackwards(text, headSize);
    combinedSample +=
        "--- [PHẦN MỞ ĐẦU] ---\n${text.substring(0, safeHeadEnd)}\n\n";

    // 2. Mid
    final int midPoint = (totalLen / 2).floor();
    int safeMidStart = _findSafeCutForwardLegacy(text, midPoint);
    int safeMidEnd = _findSafeCutBackwards(text, safeMidStart + midSize);

    // Ensure we don't go out of bounds or overlap weirdly
    if (safeMidStart < safeHeadEnd) safeMidStart = safeHeadEnd;
    if (safeMidEnd > totalLen) safeMidEnd = totalLen;

    if (safeMidEnd > safeMidStart) {
      combinedSample +=
          "--- [PHẦN GIỮA TRUYỆN] ---\n... ${text.substring(safeMidStart, safeMidEnd)} ...\n\n";
    }

    // 3. Tail
    int startTail = totalLen - tailSize;
    if (startTail < safeMidEnd) startTail = safeMidEnd;

    int safeTailStart = _findSafeCutForwardLegacy(text, startTail);
    combinedSample +=
        "--- [PHẦN KẾT THÚC] ---\n... ${text.substring(safeTailStart, totalLen)}";

    return combinedSample;
  }

  static int _findSafeCutBackwards(String text, int limitIndex) {
    for (int i = 0; i < 500; i++) {
      final int idx = limitIndex - i;
      if (idx < 0) return 0;

      if (_safeChars.contains(text[idx])) {
        return idx + 1;
      }
    }
    // Fallback to space
    final int lastSpace = text.lastIndexOf(' ', limitIndex);
    return lastSpace != -1 ? lastSpace : limitIndex;
  }

  static int _findSafeCutForwardLegacy(String text, int startIndex) {
    for (int i = 0; i < 500; i++) {
      final int idx = startIndex + i;
      if (idx >= text.length) return text.length;

      if (_safeChars.contains(text[idx])) {
        return idx + 1;
      }
    }
    // Fallback to space
    final int firstSpace = text.indexOf(' ', startIndex);
    return firstSpace != -1 ? firstSpace + 1 : startIndex;
  }
}
