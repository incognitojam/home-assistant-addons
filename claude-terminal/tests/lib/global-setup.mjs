import { assertImageExists } from './container.mjs';
import { IMAGE } from './fixtures.mjs';

export default async function globalSetup() {
    await assertImageExists(IMAGE);
}
