import { expect, test } from '@playwright/test'

test.beforeEach(async ({ page }) => {
  page.on('console', message => console.log(`browser ${message.type()}: ${message.text()}`))
  page.on('pageerror', error => console.log(`browser error: ${error.message}`))
  page.on('websocket', socket => {
    console.log(`websocket opened: ${socket.url()}`)
    socket.on('close', () => console.log(`websocket closed: ${socket.url()}`))
  })
})

test('plain HTML replaces the connection content by default', async ({ page }) => {
  await page.goto('/browser/default')
  await page.getByRole('button', { name: 'Send plain' }).click()
  await expect(page.locator('#connection')).toHaveText('plain reply')
  await expect(page.locator('#original')).toHaveCount(0)
})

test('connection target and swap attributes append plain HTML', async ({ page }) => {
  await page.goto('/browser/attributes')
  await page.getByRole('button', { name: 'Send plain' }).click()
  await expect(page.locator('#messages')).toContainText('first')
  await expect(page.locator('#messages')).toContainText('plain reply')
})

test('an envelope overrides connection target and swap attributes', async ({ page }) => {
  await page.goto('/browser/override')
  await page.getByRole('button', { name: 'Send override' }).click()
  await expect(page.locator('#override-target')).toHaveText('override reply')
  await expect(page.locator('#wrong-target')).toHaveText('wrong')
})

test('hx-partial updates another region and leaves the connection unchanged', async ({ page }) => {
  await page.goto('/browser/partial')
  await page.getByRole('button', { name: 'Send partial' }).click()
  await expect(page.locator('#secondary')).toHaveText('partial reply')
  await expect(page.locator('#stable')).toHaveText('stable')
})

test('hx-swap-oob updates a region by id', async ({ page }) => {
  await page.goto('/browser/oob')
  await page.getByRole('button', { name: 'Send OOB' }).click()
  await expect(page.locator('#oob-target')).toHaveText('oob reply')
  await expect(page.locator('#stable')).toHaveText('stable')
})

test('a submitted message is broadcast to two real htmx clients', async ({ browser }) => {
  const firstContext = await browser.newContext()
  const secondContext = await browser.newContext()
  const first = await firstContext.newPage()
  const second = await secondContext.newPage()

  await Promise.all([first.goto('/'), second.goto('/')])
  await first.getByLabel('Message').fill('hello from htmx')
  await first.getByRole('button', { name: 'Send' }).click()

  await expect(first.locator('#messages')).toContainText('hello from htmx')
  await expect(second.locator('#messages')).toContainText('hello from htmx')

  await Promise.all([firstContext.close(), secondContext.close()])
})

test('visibility pause reconnects and mounts a fresh socket', async ({ page }) => {
  await page.goto('/browser/reconnect')
  await expect(page.locator('#mount-count')).not.toHaveText('0')
  const firstCount = Number(await page.locator('#mount-count').textContent())

  await setVisibility(page, 'hidden')
  await setVisibility(page, 'visible')

  await expect
    .poll(async () => Number(await page.locator('#mount-count').textContent()))
    .toBeGreaterThan(firstCount)

  await page.getByRole('button', { name: 'Send after reconnect' }).click()
  await expect(page.locator('#connection')).toContainText('plain reply')
})

async function setVisibility(page: import('@playwright/test').Page, state: 'hidden' | 'visible') {
  await page.evaluate(value => {
    Object.defineProperty(document, 'hidden', {
      configurable: true,
      value: value === 'hidden',
    })
    Object.defineProperty(document, 'visibilityState', {
      configurable: true,
      value,
    })
    document.dispatchEvent(new Event('visibilitychange'))
  }, state)
}
