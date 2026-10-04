// SPDX-License-Identifier: GPL-2.0+
/* Receive BOOT.BIN in DDR through JTAG, verify it, then overwrite SD FAT. */
#include <command.h>
#include <cpu_func.h>
#include <fs.h>
#include <linux/delay.h>
#include <linux/kernel.h>
#include <u-boot/crc.h>
#include <asm/cache.h>

#define JTAG_DESC_ADDR       0x07fff000UL
#define JTAG_DATA_ADDR       0x08000000UL
#define JTAG_DATA_MAX        (32UL * 1024 * 1024)
#define JTAG_DESC_MAGIC      0x4a534455U
#define JTAG_DESC_VERSION    1U
#define JTAG_WAIT_MS         120000U

struct jtag_sd_descriptor {
	u32 magic;
	u32 version;
	u32 address;
	u32 size;
	u32 crc32;
	u32 size_inverse;
	u32 reserved[10];
};

static int select_sd_fat(void)
{
	return fs_set_blk_dev("mmc", "0:1", FS_TYPE_FAT);
}

static int do_jtag_sd_update(struct cmd_tbl *cmdtp, int flag, int argc,
			     char *const argv[])
{
	volatile struct jtag_sd_descriptor *wire =
		(volatile struct jtag_sd_descriptor *)JTAG_DESC_ADDR;
	struct jtag_sd_descriptor desc;
	loff_t transferred;
	u32 calculated_crc;
	unsigned int elapsed;
	int ret;

	if (argc != 1)
		return CMD_RET_USAGE;
	wire->magic = 0;
	flush_dcache_range(JTAG_DESC_ADDR, JTAG_DESC_ADDR + sizeof(desc));
	printf("JTAG-SD: waiting up to 120 s for BOOT.BIN\n");
	for (elapsed = 0; elapsed < JTAG_WAIT_MS; elapsed += 10) {
		invalidate_dcache_range(JTAG_DESC_ADDR,
					JTAG_DESC_ADDR + sizeof(desc));
		memcpy(&desc, (const void *)wire, sizeof(desc));
		if (desc.magic == JTAG_DESC_MAGIC)
			break;
		mdelay(10);
	}
	if (elapsed == JTAG_WAIT_MS)
		goto fail;
	if (desc.version != JTAG_DESC_VERSION || desc.address != JTAG_DATA_ADDR ||
	    !desc.size || desc.size > JTAG_DATA_MAX ||
	    desc.size_inverse != ~desc.size)
		goto fail;
	invalidate_dcache_range(JTAG_DATA_ADDR,
				ALIGN(JTAG_DATA_ADDR + desc.size, ARCH_DMA_MINALIGN));
	calculated_crc = crc32(0, (const unsigned char *)JTAG_DATA_ADDR, desc.size);
	if (calculated_crc != desc.crc32)
		goto fail;
	if (run_command("mmc dev 0", 0) || run_command("mmc rescan", 0) ||
	    select_sd_fat())
		goto fail;

	/* Requested behavior: replace BOOT.BIN directly; do not create a backup. */
	fs_unlink("BOOT.BIN");
	if (select_sd_fat())
		goto fail;
	ret = fs_write("BOOT.BIN", JTAG_DATA_ADDR, 0, desc.size, &transferred);
	if (ret || transferred != desc.size)
		goto fail;
	if (select_sd_fat())
		goto fail;
	ret = fs_read("BOOT.BIN", JTAG_DATA_ADDR, 0, desc.size, &transferred);
	if (ret || transferred != desc.size)
		goto fail;
	calculated_crc = crc32(0, (const unsigned char *)JTAG_DATA_ADDR, desc.size);
	if (calculated_crc != desc.crc32)
		goto fail;
	printf("JTAG-SD: SUCCESS, BOOT.BIN=%u bytes CRC32=%08x (no backup)\n",
	       desc.size, desc.crc32);
	printf("JTAG-SD: boot.scr and image.ub were not changed\n");
	return CMD_RET_SUCCESS;
fail:
	printf("JTAG-SD: FAILED; BOOT.BIN may be absent or incomplete\n");
	return CMD_RET_FAILURE;
}

U_BOOT_CMD(jtag_sd_update, 1, 0, do_jtag_sd_update,
	"overwrite only BOOT.BIN through JTAG (no backup)",
	"\nRun this first, then run jtag-copy-boot-to-sd on the PC.");
