/**
 * Required Environment Variables:
 * - FASTLINK_USERNAME: The username/email for Fastlink login
 * - FASTLINK_PASSWORD: The password for Fastlink login
 * 
 * Optional Environment Variables:
 * - BARK_SERVER: The Bark server URL for notifications
 * - BARK_DEVICE_KEY: The Bark device key for notifications
 */

addEventListener("scheduled", (event) => {
  event.waitUntil(handleScheduledEvent(event));
});

addEventListener("fetch", (event) => {
  event.respondWith(handleFetchEvent(event));
});

async function handleFetchEvent(event) {
  try {
    const url = new URL(event.request.url);
    const testBark = url.searchParams.get('bark') === 'true';
    const result = await handleCheckinProcess(testBark);
    return new Response(result, {
      headers: { "Content-Type": "text/plain" },
    });
  } catch (error) {
    return new Response(`Error: ${error.message}`, {
      status: 500,
      headers: { "Content-Type": "text/plain" },
    });
  }
}

async function handleScheduledEvent(event) {
  try {
    await handleCheckinProcess();
  } catch (error) {
    console.error("Error during scheduled event:", error);
  }
}

async function handleCheckinProcess(forceBark = false) {
  let resultMsg = [];
  const loginCookies = await login();
  
  if (!loginCookies) {
    const msg = "Login failed: No cookies received or login credentials are incorrect";
    console.log(msg);
    return msg;
  }

  const homePageInfo = await checkUserHomePage(loginCookies);
  if (!homePageInfo) {
    const msg = "Failed to get homepage info";
    console.log(msg);
    return msg;
  }

  // Format next reset date
  const nextResetDate = getNextResetDate(homePageInfo.expiryDate);
  const formattedResetDate = nextResetDate.toISOString().split('T')[0];

  resultMsg.push(`Today Used: ${homePageInfo.usedToday}`);
  resultMsg.push(`Unused Traffic: ${homePageInfo.unusedTraffic || homePageInfo.remainingTraffic}`);
  resultMsg.push(`Days Until Reset: ${homePageInfo.daysUntilReset} days`);
  resultMsg.push(`Next Reset: ${formattedResetDate}`);

  if (homePageInfo.canCheckIn) {
    const checkinMsg = await checkin(loginCookies);
    resultMsg.push(`Check-in Status: ${checkinMsg}`);
    if ((typeof BARK_SERVER !== 'undefined' && typeof BARK_DEVICE_KEY !== 'undefined') || forceBark) {
      await sendBarkNotification(checkinMsg, homePageInfo, false);
    }
  } else {
    const msg = "Already checked in for today.";
    resultMsg.push(`Check-in Status: ${msg}`);
    if ((typeof BARK_SERVER !== 'undefined' && typeof BARK_DEVICE_KEY !== 'undefined') || forceBark) {
      await sendBarkNotification("", homePageInfo, true);
    }
  }

  return resultMsg.join("\n");
}

async function login() {
  // Check if credentials are set
  if (!FASTLINK_USERNAME || !FASTLINK_PASSWORD) {
    console.error(
      "Error: Username or Password not set in environment variables",
    );
    return null;
  }

  const loginUrl = "http://fastlink.pro/auth/login";
  const headers = {
    Accept: "application/json, text/javascript, */*; q=0.01",
    "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
  };
  const email = FASTLINK_USERNAME;
  const password = FASTLINK_PASSWORD;
  const body = `email=${encodeURIComponent(email)}&passwd=${encodeURIComponent(password)}&code=&remember_me=on`;

  const response = await fetch(loginUrl, {
    method: "POST",
    headers: headers,
    body: body,
  });

  if (response.ok) {
    let cookies = [];
    response.headers.forEach((value, name) => {
      if (name === "set-cookie") {
        cookies.push(value.split(";")[0]);
      }
    });
    const cookiesStr = cookies.join("; ");
    console.log("Login success:", cookiesStr);
    return cookiesStr;
  } else {
    console.error("Login failed:", response.status, response.statusText);
    return null;
  }
}

async function checkin(cookies) {
  const checkinUrl = "http://fastlink.pro/user/checkin";
  const headers = {
    Accept: "application/json, text/javascript, */*; q=0.01",
    Cookie: cookies,
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
  };

  const response = await fetch(checkinUrl, {
    method: "POST",
    headers: headers,
  });

  if (response.ok) {
    const responseData = await response.json();
    // Decode Chinese text using decodeURIComponent
    try {
      return decodeURIComponent(escape(responseData.msg));
    } catch (e) {
      return responseData.msg;
    }
  } else {
    console.error("Check-in failed:", response.status, response.statusText);
    return "Check-in failed";
  }
}

async function checkUserHomePage(cookies) {
  const userUrl = "http://fastlink.pro/user";
  const headers = {
    Accept:
      "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
    Cookie: cookies,
  };

  const response = await fetch(userUrl, {
    method: "GET",
    headers: headers,
  });

  if (response.ok) {
    const respText = await response.text();
    try {
      const homePageData = extractHomePageData(respText);
      console.log("User's home page info:", homePageData);
      return homePageData;
    } catch (e) {
      console.log("Failed to parse user's home page info: ", e);
      return null;
    }
  } else {
    console.error(
      "Failed to access user home page:",
      response.status,
      response.statusText,
    );
    return null;
  }
}

function extractHomePageData(html) {
  let canCheckIn = !html.includes('明日再来');
  let { totalTraffic, usedToday, remainingTraffic } = extractTrafficData(html);
  let { unusedTraffic, expiryDate } = extractUserData(html);
  
  // Calculate days
  const now = new Date();
  const nextReset = new Date(now.getFullYear(), now.getMonth(), 25);
  if (now.getDate() >= 25) {
    nextReset.setMonth(nextReset.getMonth() + 1);
  }
  const daysUntilReset = Math.ceil((nextReset - now) / (1000 * 60 * 60 * 24));

  return { 
    canCheckIn, 
    totalTraffic, 
    usedToday, 
    remainingTraffic,
    unusedTraffic,
    daysUntilReset,
    expiryDate
  };
}

function extractTrafficData(html) {
  const trafficDataRegex =
    /trafficDountChat\(\s*'([^']*)',\s*'([^']*)',\s*'([^']*)',/;
  const match = trafficDataRegex.exec(html);

  if (match && match.length >= 4) {
    // Add fallback values if any field is empty
    return {
      totalTraffic: match[1].trim() || "0GB",
      usedToday: match[2].trim() || "0MB",
      remainingTraffic: match[3].trim() || "0GB",
    };
  }
  return { totalTraffic: "0GB", usedToday: "0MB", remainingTraffic: "0GB" };
}

function extractUserData(html) {
  let unusedTraffic = "0GB";
  let expiryDate = "";
  
  // Extract unused traffic from Crisp data
  const unusedMatch = html.match(/\["Unused_Traffic",\s*"([^"]+)"\]/);
  if (unusedMatch) {
    unusedTraffic = unusedMatch[1];
  }
  
  // Extract expiry date from Crisp data
  const expiryMatch = html.match(/\["Class_Expire",\s*"([^"]+)"\]/);
  if (expiryMatch) {
    expiryDate = expiryMatch[1];
  }
  
  return { unusedTraffic, expiryDate };
}

function getNextResetDate(expiryDate) {
  const now = new Date();
  const currentMonth = now.getMonth();
  const currentYear = now.getFullYear();
  
  // If we have expiry date, use its day as reset day
  if (expiryDate) {
    const expiry = new Date(expiryDate);
    const resetDay = expiry.getDate();
    const resetDate = new Date(currentYear, currentMonth, resetDay);
    
    // If we've passed this month's reset date, move to next month
    if (now.getDate() >= resetDay) {
      resetDate.setMonth(resetDate.getMonth() + 1);
    }
    
    return resetDate;
  }
  
  // Fallback to 25th if no expiry date
  const resetDate = new Date(currentYear, currentMonth, 25);
  if (now.getDate() >= 25) {
    resetDate.setMonth(resetDate.getMonth() + 1);
  }
  return resetDate;
}

async function sendBarkNotification(
  checkinMsg,
  { usedToday, unusedTraffic, remainingTraffic, daysUntilReset, expiryDate },
  alreadyCheckedIn,
) {
  // Check if Bark notification is properly configured
  if (typeof BARK_SERVER === 'undefined' || typeof BARK_DEVICE_KEY === 'undefined') {
    console.log("Bark notification skipped: BARK_SERVER or BARK_DEVICE_KEY not configured");
    return;
  }

  const title = "Fastlink Status";
  const traffic = unusedTraffic || remainingTraffic;
  const nextResetDate = getNextResetDate(expiryDate);
  const formattedResetDate = nextResetDate.toISOString().split('T')[0];
  let body;

  if (alreadyCheckedIn) {
    body = `Already checked in | Used: ${usedToday} | Remaining: ${traffic} | Next Reset: ${formattedResetDate}`;
  } else {
    body = `${checkinMsg} | Used: ${usedToday} | Remaining: ${traffic} | Next Reset: ${formattedResetDate}`;
  }

  const barkUrl = `${BARK_SERVER}/push`;
  const data = {
    title: title,
    body: body,
    group: "fastlink",
    device_key: BARK_DEVICE_KEY,
  };

  const response = await fetch(barkUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(data),
  });

  if (response.ok) {
    console.log("Bark notification sent successfully");
  } else {
    const respText = await response.text();
    console.error(
      "Failed to send Bark notification:",
      response.status,
      response.statusText,
      respText,
    );
  }
}
