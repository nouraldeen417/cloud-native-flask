-- Azure MySQL Flexible Server version.
-- DEFINER clauses removed: Azure's managed admin account lacks SUPER/SET_USER_ID
-- privilege required to create routines with an explicit DEFINER. Omitting it
-- defaults to DEFINER=CURRENT_USER, which works under the managed admin login.
-- Also assumes the database already exists (created via Terraform's
-- azurerm_mysql_flexible_database resource) rather than creating it here.

USE BucketList;

CREATE TABLE `tbl_user` (
  `user_id` BIGINT NOT NULL AUTO_INCREMENT,
  `user_name` VARCHAR(45) NULL,
  `user_username` VARCHAR(45) NULL,
  `user_password` VARCHAR(45) NULL,
  PRIMARY KEY (`user_id`));

INSERT INTO tbl_user
VALUES
(10,'ahmed','ahmed','ahmed');


DELIMITER $$
CREATE PROCEDURE `sp_createUser`(
    IN p_name VARCHAR(20),
    IN p_username VARCHAR(100),
    IN p_password VARCHAR(20)
)
BEGIN
    IF ( SELECT EXISTS (SELECT 1 FROM tbl_user WHERE user_username = p_username) ) THEN
        SELECT 'Username Exists !!';
    ELSE
        INSERT INTO tbl_user
        (
            user_name,
            user_username,
            user_password
        )
        VALUES
        (
            p_name,
            p_username,
            p_password
        );
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE PROCEDURE `sp_validateLogin`(
    IN p_username VARCHAR(20)
)
BEGIN
    SELECT * FROM tbl_user WHERE user_username = p_username;
END$$
DELIMITER ;


CREATE TABLE `tbl_wish` (
  `wish_id` INT(11) NOT NULL AUTO_INCREMENT,
  `wish_title` VARCHAR(45) DEFAULT NULL,
  `wish_description` VARCHAR(5000) DEFAULT NULL,
  `wish_user_id` INT(11) DEFAULT NULL,
  `wish_date` DATETIME DEFAULT NULL,
  PRIMARY KEY (`wish_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=latin1;


DROP PROCEDURE IF EXISTS `sp_addWish`;
DELIMITER $$
CREATE PROCEDURE `sp_addWish`(
    IN p_title VARCHAR(45),
    IN p_description VARCHAR(1000),
    IN p_user_id BIGINT
)
BEGIN
    INSERT INTO tbl_wish(
        wish_title,
        wish_description,
        wish_user_id,
        wish_date
    )
    VALUES
    (
        p_title,
        p_description,
        p_user_id,
        NOW()
    );
END$$
DELIMITER ;


DROP PROCEDURE IF EXISTS `sp_GetWishByUser`;
DELIMITER $$
CREATE PROCEDURE `sp_GetWishByUser` (
    IN p_user_id BIGINT
)
BEGIN
    SELECT * FROM tbl_wish WHERE wish_user_id = p_user_id;
END$$
DELIMITER ;