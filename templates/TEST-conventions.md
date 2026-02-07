# WebdriverIO Test Conventions

Reference for generating E2E tests with WebdriverIO and tauri-driver.

## File Structure

```javascript
/**
 * [Feature Name] E2E Tests
 * 
 * Generated from: specs/feature/SPEC.md
 * Generated on: YYYY-MM-DD HH:MM
 * 
 * [Brief description of what this tests]
 */

describe("[Feature Name]", () => {
  
  describe("[Scenario Group]", () => {
    beforeEach(async () => {
      // Reset state before each test
      await browser.reloadSession();
      await browser.pause(2000);
    });

    it("should [specific behavior]", async () => {
      // Arrange - set up test conditions
      // Act - perform the action
      // Assert - verify the result
    });
  });
});
```

## Selector Priority

Use selectors in this order (most reliable first):

1. **Accessibility attributes**
   ```javascript
   await $("[aria-label='Submit button']");
   await $("[role='progressbar']");
   ```

2. **Test IDs** (if available in the app)
   ```javascript
   await $("[data-testid='profile-form']");
   ```

3. **Text content matching**
   ```javascript
   await $("button*=Get Started");  // Contains "Get Started"
   await $("h1=Welcome");           // Exact match
   ```

4. **Semantic HTML**
   ```javascript
   await $("h1");
   await $("input");
   await $("button");
   ```

5. **XPath (last resort)**
   ```javascript
   await $("//span[contains(text(), 'Privacy')]");
   ```

## Timing Patterns

### Wait for element existence
```javascript
const element = await $("selector");
await element.waitForExist({ timeout: 5000 });
```

### Wait before clicking
```javascript
const button = await $("button*=Submit");
await button.waitForClickable({ timeout: 5000 });
await button.click();
```

### Pause after transitions
```javascript
await button.click();
await browser.pause(500);  // Wait for animation/navigation
```

### App load wait
```javascript
beforeEach(async () => {
  await browser.pause(2000);  // App initialization
});
```

### Reset session for fresh state
```javascript
await browser.reloadSession();
await browser.pause(2000);
```

## Assertions

### Text content
```javascript
const heading = await $("h1");
const text = await heading.getText();
expect(text).toContain("Welcome");      // Partial match
expect(text).toBe("Welcome to App");    // Exact match
```

### Element existence
```javascript
const element = await $("selector");
const exists = await element.isExisting();
expect(exists).toBe(true);
```

### Input values
```javascript
const input = await $("input");
const value = await input.getValue();
expect(value).toBe("entered text");
```

### Visibility
```javascript
const element = await $("selector");
const isDisplayed = await element.isDisplayed();
expect(isDisplayed).toBe(true);
```

### Attributes
```javascript
const element = await $("selector");
const ariaLabel = await element.getAttribute("aria-label");
expect(ariaLabel).toContain("Step");
```

## Debugging

### Log key values
```javascript
const text = await heading.getText();
console.log("Found heading:", text);
expect(text).toContain("Welcome");
```

### Log navigation state
```javascript
await button.click();
console.log("✓ Clicked button, navigating...");
await browser.pause(500);
```

## Test Independence

Each test MUST work when run alone:

```javascript
describe("Feature", () => {
  beforeEach(async () => {
    // ALWAYS reset to known state
    await browser.reloadSession();
    await browser.pause(2000);
  });

  it("first test", async () => {
    // Works alone
  });

  it("second test", async () => {
    // Also works alone - doesn't depend on "first test"
  });
});
```

## Multi-step Navigation

For tests that need to navigate through steps:

```javascript
it("should complete multi-step flow", async () => {
  // Step 1: Start
  const startBtn = await $("button*=Get Started");
  await startBtn.waitForClickable({ timeout: 5000 });
  await startBtn.click();
  await browser.pause(500);
  
  // Step 2: Fill form
  const input = await $("input");
  await input.waitForExist({ timeout: 5000 });
  await input.setValue("Test");
  
  // Step 3: Continue
  const nextBtn = await $("button*=Continue");
  await nextBtn.waitForClickable({ timeout: 5000 });
  await nextBtn.click();
  await browser.pause(500);
  
  // Assert final state
  const result = await $(".success-message");
  await result.waitForExist({ timeout: 5000 });
  expect(await result.getText()).toContain("Done");
});
```

## Common Patterns

### Form input
```javascript
const input = await $("input[type='text']");
await input.waitForExist({ timeout: 5000 });
await input.setValue("test value");
```

### Button click
```javascript
const button = await $("button*=Submit");
await button.waitForClickable({ timeout: 5000 });
await button.click();
```

### Check element not present
```javascript
const element = await $("selector");
const exists = await element.isExisting();
expect(exists).toBe(false);
```

### Navigate back
```javascript
const backBtn = await $("button*=Back");
await backBtn.waitForClickable({ timeout: 5000 });
await backBtn.click();
await browser.pause(500);

// Verify we're back
const previousElement = await $("previous-page-selector");
await previousElement.waitForExist({ timeout: 5000 });
```
