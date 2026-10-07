# Cập nhật pmufw.bin trên SD qua UART

Build bằng `bash tools/petalinux-setup/build-uboot.sh`. ELF mới nằm ở
`vivado/ibex_min/uboot/u-boot-ibex.elf`; cần đóng gói lại BOOT.BIN với ELF này
và FSBL/bitstream phù hợp, rồi khởi động bo bằng BOOT.BIN mới.

Bản build bật MMC/SDHCI Zynq, phân vùng DOS, đọc/ghi FAT và
`CONFIG_CMD_LOADB` (cung cấp cả `loadb`, `loadx`, `loady`).

1. Mở terminal UART ở 115200 baud, 8N1, tắt flow control. Nhấn phím trong
   thời gian đếm ngược để dừng autoboot ở dấu nhắc U-Boot.
2. Kiểm tra SD và phân vùng FAT. Các ví dụ dùng `mmc 0:1`; nếu bố cục thẻ
   khác thì thay số thiết bị/phân vùng theo kết quả `mmc list` và `mmc part`.

   ```text
   mmc list
   mmc dev 0
   mmc rescan
   mmc part
   fatls mmc 0:1
   loady 0x08000000 115200
   ```

3. Khi hiện thông báo chờ YMODEM, dùng chức năng **Send file / YMODEM** của
   terminal (ví dụ Tera Term) để gửi một file `pmufw.bin`. Chờ truyền thành
   công rồi mới chạy bước tiếp theo. `filesize` là kích thước nhận, dạng hex;
   firmware phải có kích thước từ 1 đến `0x4000` byte (16 KiB).

   ```text
   echo ${filesize}
   setenv pmufw_size ${filesize}
   ```

   Kiểm tra kích thước nằm trong giới hạn trên, rồi ghi file:

   ```text
   fatwrite mmc 0:1 0x08000000 pmufw.bin ${pmufw_size}
   ```

4. Sau khi `fatwrite` báo ghi thành công, đọc lại vào vùng RAM khác để so
   sánh. Chỉ reset khi `cmp.b` báo dữ liệu giống nhau và kích thước đọc lại
   bằng `pmufw_size`.

   ```text
   fatload mmc 0:1 0x08100000 pmufw.bin
   echo ${filesize} ${pmufw_size}
   cmp.b 0x08000000 0x08100000 ${pmufw_size}
   reset
   ```

`fatwrite` thay nội dung file firmware trên SD. FSBL nạp firmware mới vào
RAM chương trình của Ibex ở lần khởi động kế tiếp. Luồng này yêu cầu đã vào
được U-Boot; nếu FSBL dừng vì thiếu/hỏng `pmufw.bin`, cần khôi phục file trên
SD bằng máy tính hoặc dùng luồng boot phục hồi trước.

Tham khảo: https://docs.u-boot.org/en/v2025.10/usage/cmd/loady.html
