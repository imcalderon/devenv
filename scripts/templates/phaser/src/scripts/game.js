import 'phaser';
import { BootScene } from './states/BootScene';
import { GameScene } from './states/GameScene';
import { LoadScene } from './states/LoadScene';
import { MenuScene } from './states/MenuScene';

const config = {
  type: Phaser.AUTO,
  parent: 'game',
  width: 800,
  height: 600,
  physics: {
    default: 'arcade',
    arcade: {
      gravity: { y: 300 },
      debug: false
    }
  },
  scene: [
    BootScene,
    LoadScene,
    MenuScene,
    GameScene
  ]
};

window.game = new Phaser.Game(config);