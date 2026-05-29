const recordButton = document.getElementById("recordButton");
const statusText = document.getElementById("statusText");
const timerText = document.getElementById("timerText");
const buttonLabel = recordButton.querySelector(".button-label");

let mediaRecorder = null;
let stream = null;
let chunks = [];
let startedAt = null;
let timerId = null;
let preferredMimeType = "";

function setStatus(message) {
  statusText.textContent = message;
}

function setBusy(isBusy) {
  recordButton.disabled = isBusy;
  recordButton.classList.toggle("is-busy", isBusy);
}

function setRecording(isRecording) {
  recordButton.classList.toggle("is-recording", isRecording);
  buttonLabel.textContent = isRecording ? "Stop Recording" : "Start Recording";
}

function updateTimer() {
  if (!startedAt) {
    timerText.textContent = "00:00";
    return;
  }

  const elapsedSeconds = Math.floor((Date.now() - startedAt) / 1000);
  const minutes = String(Math.floor(elapsedSeconds / 60)).padStart(2, "0");
  const seconds = String(elapsedSeconds % 60).padStart(2, "0");
  timerText.textContent = `${minutes}:${seconds}`;
}

function startTimer() {
  startedAt = Date.now();
  updateTimer();
  timerId = window.setInterval(updateTimer, 250);
}

function stopTimer() {
  startedAt = null;
  if (timerId) {
    clearInterval(timerId);
    timerId = null;
  }
  updateTimer();
}

function pickMimeType() {
  const candidates = [
    "audio/webm;codecs=opus",
    "audio/webm",
    "video/mp4",
    "audio/mp4",
  ];

  return candidates.find((type) => window.MediaRecorder?.isTypeSupported?.(type)) || "";
}

async function startRecording() {
  if (!navigator.mediaDevices?.getUserMedia || !window.MediaRecorder) {
    setStatus("This browser does not support in-page recording.");
    return;
  }

  setBusy(true);
  setStatus("Requesting microphone access...");

  try {
    stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    chunks = [];
    preferredMimeType = pickMimeType();

    mediaRecorder = preferredMimeType
      ? new MediaRecorder(stream, { mimeType: preferredMimeType })
      : new MediaRecorder(stream);

    mediaRecorder.addEventListener("dataavailable", (event) => {
      if (event.data && event.data.size > 0) {
        chunks.push(event.data);
      }
    });

    mediaRecorder.addEventListener("stop", async () => {
      const actualMimeType = preferredMimeType || mediaRecorder.mimeType || "audio/webm";
      const blob = new Blob(chunks, { type: actualMimeType });
      await uploadRecording(blob, actualMimeType);
      cleanupStream();
    });

    mediaRecorder.start();
    startTimer();
    setRecording(true);
    setStatus("Recording...");
  } catch (error) {
    console.error(error);
    setStatus("Microphone access failed.");
    cleanupStream();
  } finally {
    setBusy(false);
  }
}

function cleanupStream() {
  if (stream) {
    stream.getTracks().forEach((track) => track.stop());
    stream = null;
  }
}

function stopRecording() {
  if (!mediaRecorder || mediaRecorder.state !== "recording") {
    return;
  }

  setRecording(false);
  setBusy(true);
  stopTimer();
  setStatus("Uploading...");
  mediaRecorder.stop();
}

async function uploadRecording(blob, mimeType) {
  try {
    const formData = new FormData();
    formData.append("audio", blob, `mobile-recording.${mimeType.includes("mp4") ? "m4a" : "webm"}`);

    const response = await fetch("/api/upload", {
      method: "POST",
      body: formData,
    });

    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload.error || "Upload failed.");
    }

    setStatus(`Uploaded: ${payload.filename}`);
  } catch (error) {
    console.error(error);
    setStatus(error.message || "Upload failed.");
  } finally {
    chunks = [];
    mediaRecorder = null;
    setBusy(false);
  }
}

recordButton.addEventListener("click", async () => {
  if (mediaRecorder?.state === "recording") {
    stopRecording();
    return;
  }

  await startRecording();
});
