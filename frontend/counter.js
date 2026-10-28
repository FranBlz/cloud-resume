const API_URL = "https://de7gk4ckdh.execute-api.us-east-1.amazonaws.com/visits";

async function updateVisitorCount() {
  const element = document.getElementById("visitor-count");
  if (!element) return;

  try {
    const response = await fetch(API_URL, {
      method: "POST",
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);

    const data = await response.json();
    if (typeof data.count !== "number") throw new Error("Unexpected response");

    element.textContent = data.count.toLocaleString("en-US");
  } catch (error) {
    console.error("Visitor counter unavailable:", error);
  }
}

updateVisitorCount();
