CREATE TABLE IF NOT EXISTS `bp_job_settings` (
  `job` VARCHAR(50) NOT NULL PRIMARY KEY,
  `roles` LONGTEXT NULL,
  `logs_channel` VARCHAR(30) NULL,
  `questions` LONGTEXT NULL,
  `promo_questions` LONGTEXT NULL,
  `updated_by` VARCHAR(100) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `bp_identities` (
  `citizenid` VARCHAR(64) NOT NULL PRIMARY KEY,
  `license` VARCHAR(60) NULL,
  `discord` VARCHAR(30) NULL,
  `steam` VARCHAR(60) NULL,
  `fivem_name` VARCHAR(100) NULL,
  `char_name` VARCHAR(100) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `discord` (`discord`)
);

CREATE TABLE IF NOT EXISTS `bp_application_peds` (
  `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `job` VARCHAR(50) NOT NULL,
  `label` VARCHAR(60) NOT NULL,
  `model` VARCHAR(60) NOT NULL,
  `scenario` VARCHAR(60) NOT NULL DEFAULT 'none',
  `x` DOUBLE NOT NULL, `y` DOUBLE NOT NULL, `z` DOUBLE NOT NULL, `h` DOUBLE NOT NULL,
  `channel_id` VARCHAR(30) NOT NULL,
  `enabled` TINYINT(1) NOT NULL DEFAULT 1,
  `created_by` VARCHAR(50) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS `bp_applications` (
  `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(64) NOT NULL,
  `job` VARCHAR(50) NOT NULL,
  `type` VARCHAR(16) NOT NULL DEFAULT 'hire',
  `from_grade` INT NULL,
  `target_grade` INT NOT NULL DEFAULT 0,
  `ped_id` INT NULL,
  `char_name` VARCHAR(100) NULL,
  `fivem_name` VARCHAR(100) NULL,
  `discord` VARCHAR(30) NULL,
  `steam` VARCHAR(60) NULL,
  `steam64` VARCHAR(30) NULL,
  `license` VARCHAR(60) NULL,
  `phone` VARCHAR(30) NULL,
  `current_job` VARCHAR(50) NULL,
  `current_grade` INT NULL,
  `answers` LONGTEXT NULL,
  `status` VARCHAR(16) NOT NULL DEFAULT 'pending',
  `reason` TEXT NULL,
  `decided_by` VARCHAR(30) NULL,
  `decided_by_name` VARCHAR(100) NULL,
  `channel_id` VARCHAR(30) NULL,
  `message_id` VARCHAR(30) NULL,
  `notified` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `decided_at` TIMESTAMP NULL,
  INDEX `citizenid` (`citizenid`),
  INDEX `job_status` (`job`, `status`)
);

CREATE TABLE IF NOT EXISTS `bp_application_logs` (
  `id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `action` VARCHAR(32) NOT NULL,
  `actor` VARCHAR(100) NULL,
  `data` LONGTEXT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);
