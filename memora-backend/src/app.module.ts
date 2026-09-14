import { Module } from '@nestjs/common';
import { AlbumsModule } from './albums/albums.module';
import { AuthModule } from './auth/auth.module';
import { HealthModule } from './health/health.module';
import { NotFoundModule } from './not-found/not-found.module';

@Module({
  // NotFoundModule stays last: its catch-all route must only match once no
  // other controller has claimed the path.
  imports: [HealthModule, AuthModule, AlbumsModule, NotFoundModule],
})
export class AppModule {}
